module field

  implicit none

  private

  public :: field__fdtd_i


contains

  
  subroutine field__fdtd_i(uf,up,gp,                                &
                           np,nsp,np2,nxgs,nxge,nxs,nxe,nys,nye,bc, &
                           q,c,delx,delt,gfac,                      &
                           nup,ndown,mnpr,opsum,nstat,ncomw,nerr)

    use boundary, only : boundary__field, boundary__curre,  boundary__particle
 
    integer, intent(in)    :: np, nsp, nxgs, nxge, nxs, nxe, nys, nye, bc
    integer, intent(in)    :: np2(nys:nye,nsp)
    integer, intent(in)    :: nup, ndown, opsum, mnpr, ncomw
    integer, intent(inout) :: nerr, nstat(:)
    real(8), intent(in)    :: q(nsp), c, delx, delt, gfac
    real(8), intent(in)    :: gp(5,np,nys:nye,nsp)
    real(8), intent(inout) :: up(5,np,nys:nye,nsp)
    real(8), intent(inout) :: uf(6,nxs-1:nxe+1,nys-1:nye+1)
    logical, save              :: lflag=.true.
    integer                    :: ii, i, j, isp
    real(8)                    :: pi, f1, f2, f3
    real(8)                    :: uj(3,nxs-2:nxe+2,nys-2:nye+2), gkl(6,nxs-1:nxe+1,nys-1:nye+1)
    real(8), save, allocatable :: gf(:,:,:)

    pi = 4.0*atan(1.0)

    if(lflag)then
       allocate(gf(6,nxs-1:nxe+1,nys-1:nye+1))
       gf(1:3,nxs-1:nxe+1,nys-1:nye+1) = 0.0
       lflag=.false.
    endif

    call ele_cur(uj,up,gp, &
                 np,nsp,np2,nxgs,nxge,nxs,nxe,nys,nye,bc,q,c,delx,delt)
    call boundary__curre(uj,nxs,nxe,nys,nye,bc, &
                         nup,ndown,mnpr,nstat,ncomw,nerr)

    !calculation
    !< gkl(1:3) =  (c*delt)*rot(e) >
    !< gkl(4:6) =  (c*delt)*rot(b) - (4*pi*delt)*j >
    f1 = c*delt/delx
    f2 = 4.0*pi*delt
!$OMP PARALLEL DO PRIVATE(i,j)
    do j=nys,nye
    do i=nxs,nxe+bc
       gkl(1,i,j) = -f1*(+(-uf(6,i,j-1)+uf(6,i,j)))
       gkl(2,i,j) = -f1*(-(-uf(6,i-1,j)+uf(6,i,j)))
       gkl(3,i,j) = -f1*(-(-uf(4,i,j-1)+uf(4,i,j))+(-uf(5,i-1,j)+uf(5,i,j)))
       gkl(4,i,j) = +f1*(+(-uf(3,i,j)+uf(3,i,j+1)))-f2*uj(1,i,j)
       gkl(5,i,j) = +f1*(-(-uf(3,i,j)+uf(3,i+1,j)))-f2*uj(2,i,j)
       gkl(6,i,j) = +f1*(-(-uf(1,i,j)+uf(1,i,j+1))+(-uf(2,i,j)+uf(2,i+1,j)))-f2*uj(3,i,j)
    enddo
    enddo
!$OMP END PARALLEL DO

    if(bc == -1)then
       i=nxe
!$OMP PARALLEL DO PRIVATE(j)
       do j=nys,nye
          gkl(2,i,j) = -f1*(-(-uf(6,i-1,j)+uf(6,i,j)))
          gkl(3,i,j) = -f1*(-(-uf(4,i,j-1)+uf(4,i,j))+(-uf(5,i-1,j)+uf(5,i,j)))
          gkl(4,i,j) = +f1*(+(-uf(3,i,j)+uf(3,i,j+1)))-f2*uj(1,i,j)
       enddo
!$OMP END PARALLEL DO
    endif

    call boundary__field(gkl,                &
                         nxs,nxe,nys,nye,bc, &
                         nup,ndown,mnpr,nstat,ncomw,nerr)

    f3 = c*delt*gfac/delx
!$OMP PARALLEL DO PRIVATE(i,j)
    do j=nys,nye
    do i=nxs,nxe+bc
       gkl(1,i,j) = gkl(1,i,j)-f3*(-gkl(6,i,j-1)+gkl(6,i,j))
       gkl(2,i,j) = gkl(2,i,j)+f3*(-gkl(6,i-1,j)+gkl(6,i,j))
       gkl(3,i,j) = gkl(3,i,j)-f3*(+gkl(4,i,j-1)-gkl(4,i,j) &
                                   -gkl(5,i-1,j)+gkl(5,i,j))
    enddo
    enddo
!$OMP END PARALLEL DO

    if(bc == -1)then
       i=nxe
!$OMP PARALLEL DO PRIVATE(j)
       do j=nys,nye
          gkl(2,i,j) = gkl(2,i,j)+f3*(-gkl(6,i-1,j)+gkl(6,i,j))
          gkl(3,i,j) = gkl(3,i,j)-f3*(+gkl(4,i,j-1)-gkl(4,i,j) &
                                      -gkl(5,i-1,j)+gkl(5,i,j))
       enddo
!$OMP END PARALLEL DO
    endif

    !solve  < bx, by & bz >
    call cgm(gf,gkl,             &
             nxs,nxe,nys,nye,bc, &
             c,delx,delt,gfac,   &
             nup,ndown,mnpr,opsum,nstat,ncomw,nerr)
    call boundary__field(gf,                 &
                         nxs,nxe,nys,nye,bc, &
                         nup,ndown,mnpr,nstat,ncomw,nerr)

    !solve  < ex, ey & ez >
!$OMP PARALLEL DO PRIVATE(i,j)
    do j=nys,nye
    do i=nxs,nxe+bc
       gf(4,i,j) = gkl(4,i,j)+f3*(-gf(3,i,j)+gf(3,i,j+1))
       gf(5,i,j) = gkl(5,i,j)-f3*(-gf(3,i,j)+gf(3,i+1,j))
       gf(6,i,j) = gkl(6,i,j)+f3*(-gf(2,i,j)+gf(2,i+1,j) &
                                  +gf(1,i,j)-gf(1,i,j+1))
    enddo
    enddo
!$OMP END PARALLEL DO
    if(bc == -1)then
       i=nxe
!$OMP PARALLEL DO PRIVATE(j)
       do j=nys,nye
          gf(4,i,j) = gkl(4,i,j)+f3*(-gf(3,i,j)+gf(3,i,j+1))
       enddo
!$OMP END PARALLEL DO
    endif

    call boundary__field(gf,                 &
                         nxs,nxe,nys,nye,bc, &
                         nup,ndown,mnpr,nstat,ncomw,nerr)

    !===== Update fields and particles ======
!$OMP PARALLEL WORKSHARE
    uf(1:6,nxs-1:nxe+1,nys-1:nye+1) = uf(1:6,nxs-1:nxe+1,nys-1:nye+1) &
                                     +gf(1:6,nxs-1:nxe+1,nys-1:nye+1)
!$OMP END PARALLEL WORKSHARE

    do isp=1,nsp
!$OMP PARALLEL DO PRIVATE(ii,j)
       do j=nys,nye
          do ii=1,np2(j,isp)
             up(1,ii,j,isp) = gp(1,ii,j,isp)
             up(2,ii,j,isp) = gp(2,ii,j,isp)
             up(3,ii,j,isp) = gp(3,ii,j,isp)
             up(4,ii,j,isp) = gp(4,ii,j,isp)
             up(5,ii,j,isp) = gp(5,ii,j,isp)
          enddo
       enddo
!$OMP END PARALLEL DO
    enddo

  end subroutine field__fdtd_i


  subroutine ele_cur(uj,up,gp, &
                     np,nsp,np2,nxgs,nxge,nxs,nxe,nys,nye,bc,q,c,delx,delt)

    integer, intent(in)  :: np, nsp, nxgs, nxge, nxs, nxe, nys, nye, bc
    integer, intent(in)  :: np2(nys:nye,nsp)
    real(8), intent(in)  :: q(nsp), c, delx, delt
    real(8), intent(in)  :: up(5,np,nys:nye,nsp), gp(5,np,nys:nye,nsp)
    real(8), intent(out) :: uj(3,nxs-2:nxe+2,nys-2:nye+2)
    
    integer :: ii, i, j, isp
    integer :: i1 ,i2 ,j1 ,j2, ih, jh
    real(8) :: x2, y2, xh, yh, xr, yr, qvx1, qvx2, qvy1, qvy2, idelt, idelx, idelx2, gam
    real(8) :: dx1, dx2, dy1, dy2, dxm1, dxm2, dym1, dym2, dx, dxm, dy, dym

    uj(1:3,nxs-2:nxe+2,nys-2:nye+2) = 0.D0
    
    !----- Charge Conservation Method for Jx, Jy ------!
    !----  Zigzag scheme (Umeda et al., CPC, 2003) ----!
    idelt = 1.D0/delt
    idelx = 1.D0/delx
    do isp=1,nsp
!$OMP PARALLEL DO PRIVATE(ii,j,i1,j1,i2,j2,ih,jh,                            &
!$OMP                     qvx1,qvx2,qvy1,qvy2,x2,y2,xh,yh,xr,yr,gam,         &
!$OMP                     dx,dxm,dy,dym,dx1,dx2,dy1,dy2,dxm1,dxm2,dym1,dym2) &
!$OMP REDUCTION(+:uj)
       do j=nys,nye
          do ii=1,np2(j,isp)

             x2  = gp(1,ii,j,isp)
             !reflective boundary condition in x
             if(bc == -1)then
                if(x2 < nxgs)then
                   x2  = 2.*nxgs-x2
                endif
                if(x2 > nxge)then
                   x2  = 2.*nxge-x2
                endif
             endif
             y2  = gp(2,ii,j,isp)

             xh  = 0.5*(up(1,ii,j,isp)+x2)
             yh  = 0.5*(up(2,ii,j,isp)+y2)

             i1  = floor(up(1,ii,j,isp)*idelx-0.5)
             j1  = floor(up(2,ii,j,isp)*idelx-0.5)
             i2  = floor(x2*idelx-0.5)
             j2  = floor(y2*idelx-0.5)

             if(i1==i2) then
                xr = xh
             else
                xr = (max(i1,i2)+0.5)*delx
             endif
             if(j1==j2) then
                yr = yh
             else
                yr = (max(j1,j2)+0.5)*delx
             endif

             qvx1 = q(isp)*(xr-up(1,ii,j,isp))*idelt
             qvy1 = q(isp)*(yr-up(2,ii,j,isp))*idelt
             qvx2 = q(isp)*(x2-xr)*idelt
             qvy2 = q(isp)*(y2-yr)*idelt

             dx1  = 0.5*(up(1,ii,j,isp)+xr)*idelx-0.5-i1
             dxm1 = 1.-dx1
             dy1  = 0.5*(up(2,ii,j,isp)+yr)*idelx-0.5-j1
             dym1 = 1.-dy1

             dx2  = 0.5*(xr+x2)*idelx-0.5-i2
             dxm2 = 1.-dx2
             dy2  = 0.5*(yr+y2)*idelx-0.5-j2
             dym2 = 1.-dy2

             !Jx and Jy
             uj(1,i1+1,j1  ) = uj(1,i1+1,j1  )+qvx1*dym1
             uj(1,i1+1,j1+1) = uj(1,i1+1,j1+1)+qvx1*dy1 
             uj(1,i2+1,j2  ) = uj(1,i2+1,j2  )+qvx2*dym2
             uj(1,i2+1,j2+1) = uj(1,i2+1,j2+1)+qvx2*dy2 
             uj(2,i1  ,j1+1) = uj(2,i1  ,j1+1)+qvy1*dxm1
             uj(2,i1+1,j1+1) = uj(2,i1+1,j1+1)+qvy1*dx1 
             uj(2,i2  ,j2+1) = uj(2,i2  ,j2+1)+qvy2*dxm2
             uj(2,i2+1,j2+1) = uj(2,i2+1,j2+1)+qvy2*dx2 

             !Jz
             gam = 1./dsqrt(1.0+(+gp(3,ii,j,isp)*gp(3,ii,j,isp) &
                                 +gp(4,ii,j,isp)*gp(4,ii,j,isp) &
                                 +gp(5,ii,j,isp)*gp(5,ii,j,isp) &
                                )/(c*c))
             ih = floor(xh-0.5)
             dx  = xh-0.5-ih
             dxm = 1.-dx
             jh = floor(yh-0.5)
             dy  = yh-0.5-jh
             dym = 1.-dy
             uj(3,ih  ,jh  ) = uj(3,ih  ,jh  )+q(isp)*gp(5,ii,j,isp)*gam*dxm*dym
             uj(3,ih+1,jh  ) = uj(3,ih+1,jh  )+q(isp)*gp(5,ii,j,isp)*gam*dx *dym
             uj(3,ih  ,jh+1) = uj(3,ih  ,jh+1)+q(isp)*gp(5,ii,j,isp)*gam*dxm*dy 
             uj(3,ih+1,jh+1) = uj(3,ih+1,jh+1)+q(isp)*gp(5,ii,j,isp)*gam*dx *dy 
          enddo
       enddo
!$OMP END PARALLEL DO
    enddo

    idelx2 = idelx*idelx
    if(bc == 0)then
!$OMP PARALLEL DO PRIVATE(i,j)
       do j=nys-2,nye+2
          do i=nxs-2,nxe+2
             uj(1,i,j) = uj(1,i,j)*idelx2
          enddo
       enddo
!$OMP END PARALLEL DO
    else if(bc == -1)then

!$OMP PARALLEL

!$OMP DO PRIVATE(i,j)
       do j=nys-2,nye+2
          i=nxs
          uj(1,i,j) = uj(1,i,j)*2.*idelx2
          do i=nxs+1,nxe-1
             uj(1,i,j) = uj(1,i,j)*idelx2
          enddo
          i=nxe
          uj(1,i,j) = uj(1,i,j)*2.*idelx2
       enddo
!$OMP END DO NOWAIT
!$OMP DO PRIVATE(i,j)
       do j=nys-2,nye+2
          do i=nxs-1,nxe
             uj(2,i,j) = uj(2,i,j)*idelx2
             uj(3,i,j) = uj(3,i,j)*idelx2
          enddo
       enddo
!$OMP END DO NOWAIT

!$OMP END PARALLEL
    else
       write(*,*)'choose bc=0 (periodic) or bc=-1 (reflective)'
       stop
    endif

  end subroutine ele_cur


  subroutine cgm(gb,gkl,             &
                 nxs,nxe,nys,nye,bc, &
                 c,delx,delt,gfac,   &
                 nup,ndown,mnpr,opsum,nstat,ncomw,nerr)

    !-----------------------------------------------------------------------
    !  #  conjugate gradient method 
    !  #  this routine will be stoped after itaration number = ite_max
    !-----------------------------------------------------------------------

    integer, intent(in)    :: nxs, nxe, nys, nye, bc
    integer, intent(in)    :: nup, ndown, mnpr, opsum, ncomw
    integer, intent(inout) :: nerr, nstat(:)
    real(8), intent(in)    :: c, delx, delt, gfac
    real(8), intent(in)    :: gkl(6,nxs-1:nxe+1,nys-1:nye+1)
    real(8), intent(inout) :: gb(6,nxs-1:nxe+1,nys-1:nye+1)
    integer, parameter :: ite_max = 100 ! maximum number of interation
    integer            :: i, ii, j, l, ite
    real(8), parameter :: err = 1d-6 
    real(8)            :: f1, f2, eps, sumr, sum, sum1, sum2, av, bv
    real(8)            :: sumr_g, sum_g, sum1_g, sum2_g
    real(8)            :: x(nxs-1:nxe+1,nys-1:nye+1), b(nxs:nxe,nys:nye)
    real(8)            :: r(nxs:nxe,nys:nye), p(nxs-1:nxe+1,nys-1:nye+1)
    real(8)            :: ap(nxs:nxe,nys:nye)
    real(8)            :: bff_snd(nxe-nxs+1), bff_rcv(nxe-nxs+1)

    do l=1,1

       ! initial guess
       ite = 0
       f2 = (delx/(c*delt*gfac))**2
       sum = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sum)
       do j=nys,nye
       do i=nxs,nxe+bc
          x(i,j) = gb(l,i,j)
          b(i,j) = f2*gkl(l,i,j)
          sum = sum+b(i,j)*b(i,j)
       enddo
       enddo
!$OMP END PARALLEL DO

       call MPI_ALLREDUCE(sum,sum_g,1,mnpr,opsum,ncomw,nerr)

       eps = dsqrt(sum_g)*err

       !------ boundary condition of x ------
!$OMP PARALLEL DO PRIVATE(i,ii)
       do i=nxs,nxe+bc
          ii = i-nxs+1
          bff_snd(ii) = x(i,nys)
       enddo
!$OMP END PARALLEL DO

       call MPI_SENDRECV(bff_snd(1),nxe+bc-nxs+1,mnpr,ndown,101, &
                         bff_rcv(1),nxe+bc-nxs+1,mnpr,nup  ,101, &
                         ncomw,nstat,nerr)

!$OMP PARALLEL

!$OMP DO PRIVATE(ii,i)
       do i=nxs,nxe+bc
          ii = i-nxs+1
          x(i,nye+1) = bff_rcv(ii)
       enddo
!$OMP END DO NOWAIT

!$OMP DO PRIVATE(ii,i)
       do i=nxs,nxe+bc
          ii = i-nxs+1
          bff_snd(ii) = x(i,nye)
       enddo
!$OMP END DO NOWAIT

!$OMP END PARALLEL

       call MPI_SENDRECV(bff_snd(1),nxe+bc-nxs+1,mnpr,nup  ,100, &
                         bff_rcv(1),nxe+bc-nxs+1,mnpr,ndown,100, &
                         ncomw,nstat,nerr)

!$OMP PARALLEL DO PRIVATE(i,ii)
       do i=nxs,nxe+bc
          ii = i-nxs+1
          x(i,nys-1) = bff_rcv(ii)
       enddo
!$OMP END PARALLEL DO

       if(bc == 0)then
!$OMP PARALLEL DO PRIVATE(j)
          do j=nys-1,nye+1
             x(nxs-1,j) = x(nxe,j)
             x(nxe+1,j) = x(nxs,j)
          enddo
!$OMP END PARALLEL DO          
       else if(bc == -1)then
!$OMP PARALLEL DO PRIVATE(j)
          do j=nys-1,nye+1
             x(nxs-1,j) = -x(nxs  ,j)
             x(nxe  ,j) = -x(nxe-1,j)
          enddo
!$OMP END PARALLEL DO
       else
          write(*,*)'choose bc=0 (periodic) or bc=-1 (reflective)'
          stop
       endif
       !------ end of -----

       f1 = 2.0+(delx/(c*delt*gfac))**2
       sumr = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sumr)
       do j=nys,nye
       do i=nxs,nxe+bc
          r(i,j) = b(i,j)+x(i,j-1)                    &
                         +x(i-1,j)-f1*x(i,j)+x(i+1,j) &
                         +x(i,j+1)
          p(i,j) = r(i,j)
          sumr = sumr+r(i,j)*r(i,j)
       enddo
       enddo
!$OMP END PARALLEL DO

       call MPI_ALLREDUCE(sumr,sumr_g,1,mnpr,opsum,ncomw,nerr)

       if(dsqrt(sumr_g) > eps)then
       
          do while(sum_g > eps)
             
             ite = ite+1

             !------boundary condition of p------
!$OMP PARALLEL DO PRIVATE(i,ii)
             do i=nxs,nxe+bc
                ii = i-nxs+1
                bff_snd(ii) = p(i,nys)
             enddo
!$OMP END PARALLEL DO

             call MPI_SENDRECV(bff_snd(1),nxe+bc-nxs+1,mnpr,ndown,101, &
                               bff_rcv(1),nxe+bc-nxs+1,mnpr,nup  ,101, &
                               ncomw,nstat,nerr)

!$OMP PARALLEL

!$OMP DO PRIVATE(i,ii)
             do i=nxs,nxe+bc
                ii = i-nxs+1
                p(i,nye+1) = bff_rcv(ii)
             enddo
!$OMP END DO NOWAIT
             
!$OMP DO PRIVATE(i,ii)
             do i=nxs,nxe+bc
                ii = i-nxs+1
                bff_snd(ii) = p(i,nye)
             enddo
!$OMP END DO NOWAIT

!$OMP END PARALLEL

             call MPI_SENDRECV(bff_snd(1),nxe+bc-nxs+1,mnpr,nup  ,100, &
                               bff_rcv(1),nxe+bc-nxs+1,mnpr,ndown,100, &
                               ncomw,nstat,nerr)

!$OMP PARALLEL DO PRIVATE(i,ii)
             do i=nxs,nxe+bc
                ii = i-nxs+1
                p(i,nys-1) = bff_rcv(ii)
             enddo
!$OMP END PARALLEL DO

             if(bc == 0)then
!$OMP PARALLEL DO PRIVATE(j)
                do j=nys-1,nye+1
                   p(nxs-1,j) = p(nxe,j)
                   p(nxe+1,j) = p(nxs,j)
                enddo
!$OMP END PARALLEL DO
             else if(bc == -1)then
!$OMP PARALLEL DO PRIVATE(j)
                do j=nys-1,nye+1
                   p(nxs-1,j) = -p(nxs  ,j)
                   p(nxe  ,j) = -p(nxe-1,j)
                enddo
!$OMP END PARALLEL DO
             else
                write(*,*)'choose bc=0 (periodic) or bc=-1 (reflective)'
                stop
             endif
             !----- end of -----
       
             sumr = 0.0
             sum2 = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sumr,sum2)
             do j=nys,nye
             do i=nxs,nxe+bc
                ap(i,j) = -p(i,j-1)                    &
                          -p(i-1,j)+f1*p(i,j)-p(i+1,j) &
                          -p(i,j+1)
                sumr = sumr+r(i,j)*r(i,j)
                sum2 = sum2+p(i,j)*ap(i,j)
             enddo
             enddo
!$OMP END PARALLEL DO

             bff_snd(1) = sumr
             bff_snd(2) = sum2
             call MPI_ALLREDUCE(bff_snd,bff_rcv,2,mnpr,opsum,ncomw,nerr)
             sumr_g = bff_rcv(1)
             sum2_g = bff_rcv(2)

             av = sumr_g/sum2_g

!$OMP PARALLEL WORKSHARE             
             x(nxs:nxe+bc,nys:nye) = x(nxs:nxe+bc,nys:nye)+av* p(nxs:nxe+bc,nys:nye)
             r(nxs:nxe+bc,nys:nye) = r(nxs:nxe+bc,nys:nye)-av*ap(nxs:nxe+bc,nys:nye)
!$OMP END PARALLEL WORKSHARE
             
             sum_g = dsqrt(sumr_g)
             if(ite >= ite_max) then
                write(6,*)'********** stop at cgm after ite_max **********'
                stop
             endif
             
             sum1 = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sum1)
             do j=nys,nye
             do i=nxs,nxe+bc
                sum1 = sum1+r(i,j)*r(i,j)
             enddo
             enddo
!$OMP END PARALLEL DO

             call MPI_ALLREDUCE(sum1,sum1_g,1,mnpr,opsum,ncomw,nerr)
             bv = sum1_g/sumr_g
             
!$OMP PARALLEL WORKSHARE
             p(nxs:nxe+bc,nys:nye) = r(nxs:nxe+bc,nys:nye)+bv*p(nxs:nxe+bc,nys:nye)
!$OMP END PARALLEL WORKSHARE
             
          enddo
       endif

!$OMP PARALLEL WORKSHARE
       gb(l,nxs:nxe+bc,nys:nye) = x(nxs:nxe+bc,nys:nye)
!$OMP END PARALLEL WORKSHARE

    end do

    do l=2,3

       ! initial guess
       ite = 0
       f2 = (delx/(c*delt*gfac))**2
       sum = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sum)
       do j=nys,nye
       do i=nxs,nxe
          x(i,j) = gb(l,i,j)
          b(i,j) = f2*gkl(l,i,j)
          sum = sum+b(i,j)*b(i,j)
       enddo
       enddo
!$OMP END PARALLEL DO

       call MPI_ALLREDUCE(sum,sum_g,1,mnpr,opsum,ncomw,nerr)

       eps = dsqrt(sum_g)*err

       !------ boundary condition of x ------
!$OMP PARALLEL DO PRIVATE(i,ii)
       do i=nxs,nxe
          ii = i-nxs+1
          bff_snd(ii) = x(i,nys)
       enddo
!$OMP END PARALLEL DO

       call MPI_SENDRECV(bff_snd(1),nxe-nxs+1,mnpr,ndown,101, &
                         bff_rcv(1),nxe-nxs+1,mnpr,nup  ,101, &
                         ncomw,nstat,nerr)

!$OMP PARALLEL

!$OMP DO PRIVATE(i,ii)
       do i=nxs,nxe
          ii = i-nxs+1
          x(i,nye+1) = bff_rcv(ii)
       enddo
!$OMP END DO NOWAIT

!$OMP DO PRIVATE(i,ii)
       do i=nxs,nxe
          ii = i-nxs+1
          bff_snd(ii) = x(i,nye)
       enddo
!$OMP END DO NOWAIT

!$OMP END PARALLEL 

       call MPI_SENDRECV(bff_snd(1),nxe-nxs+1,mnpr,nup  ,100, &
                         bff_rcv(1),nxe-nxs+1,mnpr,ndown,100, &
                         ncomw,nstat,nerr)

!$OMP PARALLEL DO PRIVATE(i,ii)
       do i=nxs,nxe
          ii = i-nxs+1
          x(i,nys-1) = bff_rcv(ii)
       enddo
!$OMP END PARALLEL DO

       if(bc == 0)then
!$OMP PARALLEL DO PRIVATE(j)
          do j=nys-1,nye+1
             x(nxs-1,j) = x(nxe,j)
             x(nxe+1,j) = x(nxs,j)
          enddo
!$OMP END PARALLEL DO
       else if(bc == -1)then
!$OMP PARALLEL DO PRIVATE(j)
          do j=nys-1,nye+1
             x(nxs-1,j) = x(nxs+1,j)
             x(nxe+1,j) = x(nxe-1,j)
          enddo
!$OMP END PARALLEL DO
       else
          write(*,*)'choose bc=0 (periodic) or bc=-1 (reflective)'
          stop
       endif
       !------ end of -----

       f1 = 2.0+(delx/(c*delt*gfac))**2
       sumr = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sumr)
       do j=nys,nye
       do i=nxs,nxe
          r(i,j) = b(i,j)+x(i,j-1)                    &
                         +x(i-1,j)-f1*x(i,j)+x(i+1,j) &
                         +x(i,j+1)
          p(i,j) = r(i,j)
          sumr = sumr+r(i,j)*r(i,j)
       enddo
       enddo
!$OMP END PARALLEL DO

       call MPI_ALLREDUCE(sumr,sumr_g,1,mnpr,opsum,ncomw,nerr)

       if(dsqrt(sumr_g) > eps)then
       
          do while(sum_g > eps)
             
             ite = ite+1

             !------boundary condition of p------
!$OMP PARALLEL DO PRIVATE(i,ii)
             do i=nxs,nxe
                ii = i-nxs+1
                bff_snd(ii) = p(i,nys)
             enddo
!$OMP END PARALLEL DO

             call MPI_SENDRECV(bff_snd(1),nxe-nxs+1,mnpr,ndown,101, &
                               bff_rcv(1),nxe-nxs+1,mnpr,nup  ,101, &
                               ncomw,nstat,nerr)
!$OMP PARALLEL

!$OMP DO PRIVATE(i,ii)
             do i=nxs,nxe
                ii = i-nxs+1
                p(i,nye+1) = bff_rcv(ii)
             enddo
!$OMP END DO NOWAIT

!$OMP DO PRIVATE(i,ii)
             do i=nxs,nxe
                ii = i-nxs+1
                bff_snd(ii) = p(i,nye)
             enddo
!$OMP END DO NOWAIT

!$OMP END PARALLEL

             call MPI_SENDRECV(bff_snd(1),nxe-nxs+1,mnpr,nup  ,100, &
                               bff_rcv(1),nxe-nxs+1,mnpr,ndown,100, &
                               ncomw,nstat,nerr)

!$OMP PARALLEL DO PRIVATE(i,ii)
             do i=nxs,nxe
                ii = i-nxs+1
                p(i,nys-1) = bff_rcv(ii)
             enddo
!$OMP END PARALLEL DO

             if(bc == 0)then
!$OMP PARALLEL DO PRIVATE(j)
                do j=nys-1,nye+1
                   p(nxs-1,j) = p(nxe,j)
                   p(nxe+1,j) = p(nxs,j)
                enddo
!$OMP END PARALLEL DO                
             else if(bc == -1)then
!$OMP PARALLEL DO PRIVATE(j)
                do j=nys-1,nye+1
                   p(nxs-1,j) = p(nxs+1,j)
                   p(nxe+1,j) = p(nxe-1,j)
                enddo
!$OMP END PARALLEL DO                
             else
                write(*,*)'choose bc=0 (periodic) or bc=-1 (reflective)'
                stop
             endif
             !----- end of -----

             sumr = 0.0
             sum2 = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sumr,sum2)      
             do j=nys,nye
             do i=nxs,nxe
                ap(i,j) = -p(i,j-1)                    &
                          -p(i-1,j)+f1*p(i,j)-p(i+1,j) &
                          -p(i,j+1)
                sumr = sumr+r(i,j)*r(i,j)
                sum2 = sum2+p(i,j)*ap(i,j)
             enddo
             enddo
!$OMP END PARALLEL DO

             bff_snd(1) = sumr
             bff_snd(2) = sum2
             call MPI_ALLREDUCE(bff_snd,bff_rcv,2,mnpr,opsum,ncomw,nerr)
             sumr_g = bff_rcv(1)
             sum2_g = bff_rcv(2)

             av = sumr_g/sum2_g

!$OMP PARALLEL WORKSHARE
             x(nxs:nxe,nys:nye) = x(nxs:nxe,nys:nye)+av* p(nxs:nxe,nys:nye)
             r(nxs:nxe,nys:nye) = r(nxs:nxe,nys:nye)-av*ap(nxs:nxe,nys:nye)
!$OMP END PARALLEL WORKSHARE
             
             sum_g = dsqrt(sumr_g)
             if(ite >= ite_max) then
                write(6,*)'********** stop at cgm after ite_max **********'
                stop
             endif
             
             sum1 = 0.0
!$OMP PARALLEL DO PRIVATE(i,j) REDUCTION(+:sum1)
             do j=nys,nye
             do i=nxs,nxe
                sum1 = sum1+r(i,j)*r(i,j)
             enddo
             enddo
!$OMP END PARALLEL DO
             call MPI_ALLREDUCE(sum1,sum1_g,1,mnpr,opsum,ncomw,nerr)
             bv = sum1_g/sumr_g

!$OMP PARALLEL WORKSHARE             
             p(nxs:nxe,nys:nye) = r(nxs:nxe,nys:nye)+bv*p(nxs:nxe,nys:nye)
!$OMP END PARALLEL WORKSHARE
             
          enddo
       endif

!$OMP PARALLEL WORKSHARE
       gb(l,nxs:nxe,nys:nye) = x(nxs:nxe,nys:nye)
!$OMP END PARALLEL WORKSHARE

    end do
    
  end subroutine cgm


end module field
