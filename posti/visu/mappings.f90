!=================================================================================================================================
! Copyright (c) 2016  Prof. Claus-Dieter Munz 
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://nrg.iag.uni-stuttgart.de/
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

!===================================================================================================================================
!> Routines to create several mappings:
!> * Mapping that contains the distribution of DG and FV elements
!> * Mappings from all available variables to the ones that should be calculated and visualized
!===================================================================================================================================
MODULE MOD_Posti_Mappings
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE Build_FV_DG_distribution
  MODULE PROCEDURE Build_FV_DG_distribution
END INTERFACE

INTERFACE Build_mapDepToCalc_mapTotalToVisu
  MODULE PROCEDURE Build_mapDepToCalc_mapTotalToVisu
END INTERFACE

INTERFACE Build_mapBCSides
  MODULE PROCEDURE Build_mapBCSides
END INTERFACE

PUBLIC:: Build_FV_DG_distribution
PUBLIC:: Build_mapDepToCalc_mapTotalToVisu
PUBLIC:: Build_mapBCSides

CONTAINS

!===================================================================================================================================
!> This routine determines the distribution of DG and FV elements in the state file.
!>  1. reads the 'ElemData' array in the state-file and fills the 'FV_Elems_loc' array.
!>  2. count the number of DG/FV elements in FV_Elems_loc.
!>  3. build the mappings (mapFVElemsToAllElems/DG) that hold the global indices of the FV/DG element indices.
!>  4. check wether the distribution of FV elements has changed
!===================================================================================================================================
SUBROUTINE Build_FV_DG_distribution(statefile)
USE MOD_Globals
USE MOD_PreProc
USE MOD_Posti_Vars
USE MOD_HDF5_Input  ,ONLY: GetArrayAndName,OpenDataFile,CloseDataFile
USE MOD_ReadInTools ,ONLY: GETSTR,CountOption
USE MOD_StringTools ,ONLY: STRICMP
USE MOD_Mesh_ReadIn ,ONLY: BuildPartition
USE MOD_Mesh_Vars   ,ONLY: nElems
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)  :: statefile
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iElem
INTEGER                        :: nElems_FV_glob
#if FV_ENABLED
INTEGER                        :: iElem2,iVar
INTEGER                        :: nVal(15)
REAL,ALLOCATABLE               :: ElemData_loc(:,:),tmp(:)
CHARACTER(LEN=255),ALLOCATABLE :: VarNamesElemData_loc(:)
#endif
!===================================================================================================================================
! Build partition to get nElems
CALL OpenDataFile(MeshFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
CALL BuildPartition() 
CALL CloseDataFile()

SDEALLOCATE(FV_Elems_loc)
ALLOCATE(FV_Elems_loc(1:nElems))
#if FV_ENABLED
IF (.NOT.DGonly) THEN
  NVisu_FV = (PP_N+1)*2-1

  CALL OpenDataFile(statefile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
  CALL GetArrayAndName('ElemData','VarNamesAdd',nVal,tmp,VarNamesElemData_loc)
  CALL CloseDataFile()
  IF (ALLOCATED(VarNamesElemData_loc)) THEN
    ALLOCATE(ElemData_loc(nVal(1),nVal(2)))
    ElemData_loc = RESHAPE(tmp,(/nVal(1),nVal(2)/))
    ! search for FV_Elems 
    FV_Elems_loc = 0
    DO iVar=1,nVal(1)
      IF (STRICMP(VarNamesElemData_loc(iVar),"FV_Elems")) THEN
        FV_Elems_loc = INT(ElemData_loc(iVar,:))
      END IF
    END DO
    DEALLOCATE(ElemData_loc,VarNamesElemData_loc,tmp)
  END IF

  nElems_FV = SUM(FV_Elems_loc)
  nElems_DG = nElems - nElems_FV

  ! build the mapping, that holds the global indices of all FV elements
  SDEALLOCATE(mapFVElemsToAllElems)
  ALLOCATE(mapFVElemsToAllElems(1:nElems_FV))
  iElem2 =1
  DO iElem=1,nElems
    IF (FV_Elems_loc(iElem).EQ.1) THEN
      mapFVElemsToAllElems(iElem2) = iElem
      iElem2 = iElem2 + 1
    END IF
  END DO ! iElem

  ! build the mapping, that holds the global indices of all DG elements
  SDEALLOCATE(mapDGElemsToAllElems)
  ALLOCATE(mapDGElemsToAllElems(1:nElems_DG))
  iElem2 =1
  DO iElem=1,nElems
    IF (FV_Elems_loc(iElem).EQ.0) THEN
      mapDGElemsToAllElems(iElem2) = iElem
      iElem2 = iElem2 + 1
    END IF
  END DO ! iElem
ELSE
#endif
  FV_Elems_loc = 0
  nElems_DG = nElems
  nElems_FV = 0
  NVisu_FV = 0

  ! build the mapping, that holds the global indices of all DG elements
  SDEALLOCATE(mapDGElemsToAllElems)
  ALLOCATE(mapDGElemsToAllElems(1:nElems_DG))
  DO iElem=1,nElems
    mapDGElemsToAllElems(iElem) = iElem
  END DO
#if FV_ENABLED
END IF
#endif


! check if the distribution of DG/FV elements has changed
changedFV_Elems=.TRUE.
IF (ALLOCATED(FV_Elems_old).AND.(SIZE(FV_Elems_loc).EQ.SIZE(FV_Elems_old))) THEN
  changedFV_Elems = .NOT.ALL(FV_Elems_loc.EQ.FV_Elems_old) 
END IF
SDEALLOCATE(FV_Elems_old)
ALLOCATE(FV_Elems_old(1:nElems))
FV_Elems_old = FV_Elems_loc

nElems_FV_glob = SUM(FV_Elems_loc)
#if USE_MPI
! check if any processor has FV elements
CALL MPI_ALLREDUCE(MPI_IN_PLACE,nElems_FV_glob,1,MPI_INTEGER,MPI_MAX,MPI_COMM_WORLD,iError)
#endif
hasFV_Elems = (nElems_FV_glob.GT.0)


END SUBROUTINE Build_FV_DG_distribution

!===================================================================================================================================
!> This routine builds the mappings from the total number of variables available for visualization to number of calculation
!> and visualization variables.
!>  1. Read 'VarName' options from the parameter file. This are the quantities that will be visualized.
!>  2. Initialize the dependecy table
!>  3. check wether gradients are needed for any quantity. If this is the case, remove the conservative quantities from the 
!>     dependecies of the primitive quantities (the primitive quantities are available directly, since the DGTimeDerivative_weakForm
!>     will be executed.
!>  4. build the 'mapDepToCalc' that holds for each quantity that will be calculated the index in 'UCalc' array (0 if not calculated)
!>  5. build the 'mapTotalToVisu' that holds for each quantity that will be visualized the index in 'UVisu' array (0 if not visualized)
!===================================================================================================================================
SUBROUTINE Build_mapDepToCalc_mapTotalToVisu()
USE MOD_Globals
USE MOD_Posti_Vars
USE MOD_ReadInTools     ,ONLY: GETSTR,CountOption
USE MOD_StringTools     ,ONLY: STRICMP
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: iVar,iVar2
CHARACTER(LEN=255)  :: VarName
CHARACTER(LEN=255)  :: BoundaryName
CHARACTER(LEN=20)   :: format
!===================================================================================================================================
! Read Varnames from parameter file and fill
!   mapTotalToVisu = map, which stores at position x the position/index of the x.th quantity in the UVisu array
!             if a quantity is not visualized it is zero
SDEALLOCATE(mapTotalToVisu)
SDEALLOCATE(mapTotalToSurfVisu)
ALLOCATE(mapTotalToVisu(1:nVarTotal))
ALLOCATE(mapTotalToSurfVisu(1:nVarTotal))
mapTotalToVisu = 0
mapTotalToSurfVisu = 0
nVarVisuTotal = 0
nVarSurfVisuTotal = 0
! Compare varnames that should be visualized with available varnames
DO iVar=1,CountOption("VarName")
  VarName = GETSTR("VarName")
  DO iVar2=1,nVarTotal
    IF (STRICMP(VarName, VarNamesTotal(iVar2))) THEN
      nVarSurfVisuTotal = nVarSurfVisuTotal + 1
      mapTotalToSurfVisu(iVar2) = nVarSurfVisuTotal
      IF (iVar2.LE.nVarDep) THEN
        IF(DepSurfaceOnly(iVar2).EQ.1) CYCLE
      END IF
      nVarVisuTotal = nVarVisuTotal + 1
      mapTotalToVisu(iVar2) = nVarVisuTotal
    END IF
  END DO
END DO

! check whether gradients are needed for any quantity
DO iVar=1,nVarDep
  IF (mapTotalToSurfVisu(iVar).GT.0) THEN
    withDGOperator = withDGOperator .OR. (DepTable(iVar,0).GT.0)
  END IF
END DO

! Calculate all dependencies:
! For each quantity copy from all quantities that this quantity depends on the dependencies.
DO iVar=1,nVarDep
  DepTable(iVar,iVar) = 1
  DO iVar2=1,iVar-1
    IF (DepTable(iVar,iVar2).EQ.1) &
      DepTable(iVar,:) = MAX(DepTable(iVar,:), DepTable(iVar2,:))
  END DO
END DO

! print the dependecy table
SWRITE(*,*) "Dependencies: ", withDGOperator
WRITE(format,'(I2)') SIZE(DepTable,2)
DO iVar=1,nVarDep
  SWRITE (*,'('//format//'I2,A)') DepTable(iVar,:), " "//TRIM(VarNamesTotal(iVar))
END DO

! Build :
!   mapDepToCalc = map, which stores at position x the position/index of the x.th quantity in the UCalc array
!             if a quantity is not calculated it is zero
SDEALLOCATE(mapDepToCalc)
ALLOCATE(mapDepToCalc(1:nVarDep))
mapDepToCalc = 0
DO iVar=1,nVarDep
  IF (mapTotalToSurfVisu(iVar).GT.0) THEN
    mapDepToCalc = MAX(mapDepToCalc,DepTable(iVar,1:nVarDep))
  END IF
END DO
! enumerate mapDepToCalc
nVarCalc = 0
DO iVar=1,nVarDep
  IF (mapDepToCalc(iVar).GT.0) THEN
    nVarCalc = nVarCalc + 1
    mapDepToCalc(iVar) = nVarCalc
  END IF
END DO

! check if any varnames changed
changedVarNames = .TRUE.
IF (ALLOCATED(mapTotalToSurfVisu_old).AND.(SIZE(mapTotalToSurfVisu).EQ.SIZE(mapTotalToSurfVisu_old))) THEN
  changedVarNames = .NOT.ALL(mapTotalToSurfVisu.EQ.mapTotalToSurfVisu_old) 
END IF
SDEALLOCATE(mapTotalToSurfVisu_old)
ALLOCATE(mapTotalToSurfVisu_old(1:nVarTotal))
mapTotalToSurfVisu_old = mapTotalToSurfVisu

! print the mappings
WRITE(format,'(I2)') nVarTotal
SWRITE (*,'(A,'//format//'I3)') "mapDepToCalc ",mapDepToCalc
SWRITE (*,'(A,'//format//'I3)') "mapTotalToVisu ",mapTotalToVisu
SWRITE (*,'(A,'//format//'I3)') "mapTotalToSurfVisu ",mapTotalToSurfVisu

! Build the mapping for the surface visualization
! mapAllBCNamesToVisuBCNames(iBC) stores the ascending visualization index of the all boundaries. 0 means no visualization.
! nBCNamesVisu is the number of boundaries to be visualized.
SDEALLOCATE(mapAllBCNamesToVisuBCNames)
ALLOCATE(mapAllBCNamesToVisuBCNames(1:nBCNamesTotal))
mapAllBCNamesToVisuBCNames = 0
nBCNamesVisu = 0
! Compare boundary names that should be visualized with available varnames
DO iVar=1,CountOption("BoundaryName")
  BoundaryName = GETSTR("BoundaryName")
  DO iVar2=1,nBCNamesTotal
    IF (STRICMP(BoundaryName, BoundaryNamesTotal(iVar2))) THEN
      mapAllBCNamesToVisuBCNames(iVar2) = nBCNamesVisu+1
      nBCNamesVisu = nBCNamesVisu + 1
    END IF
  END DO
END DO

! check if any boundary changed
changedBCnames = .TRUE.
IF (ALLOCATED(mapAllBCNamesToVisuBCNames_old).AND.(SIZE(mapAllBCNamesToVisuBCNames).EQ.SIZE(mapAllBCNamesToVisuBCNames_old))) THEN
  changedBCnames = .NOT.ALL(mapAllBCNamesToVisuBCNames.EQ.mapAllBCNamesToVisuBCNames_old) 
END IF
SDEALLOCATE(mapAllBCNamesToVisuBCNames_old)
ALLOCATE(mapAllBCNamesToVisuBCNames_old(1:nBCNamesTotal))
mapAllBCNamesToVisuBCNames_old = mapAllBCNamesToVisuBCNames


SWRITE (*,'(A,'//format//'I3)') "mapAllBCNamesToVisuBCNames ",mapAllBCNamesToVisuBCNames

END SUBROUTINE Build_mapDepToCalc_mapTotalToVisu

SUBROUTINE Build_mapBCSides() 
USE MOD_Posti_Vars
USE MOD_Mesh_Vars  ,ONLY: nBCSides,BC,SideToElem,BoundaryName
USE MOD_StringTools ,ONLY: STRICMP
#if FV_ENABLED
USE MOD_FV_Vars    ,ONLY: FV_Elems
#endif
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER           :: iBC,iElem,iSide
!===================================================================================================================================

! Build surface visualization mappings. 
! mapAllBCSidesToDGBCSides/FV(iBCSide) contains the ascending index of the visualization boundary sides. They are sorted after the boundary name.
! 0 means no visualization of this boundary side.
! nSidesPerBCNameVisu_DG/FV(iBCNamesVisu) contains how many boundary sides belong to each boundary that should be visualized.
SDEALLOCATE(mapAllBCSidesToDGBCSides)
SDEALLOCATE(mapAllBCSidesToFVBCSides)
SDEALLOCATE(nSidesPerBCNameVisu_DG)
SDEALLOCATE(nSidesPerBCNameVisu_FV)
ALLOCATE(mapAllBCSidesToDGBCSides(1:nBCSides))
ALLOCATE(mapAllBCSidesToFVBCSides(1:nBCSides))
ALLOCATE(nSidesPerBCNameVisu_DG(1:nBCNamesVisu))
ALLOCATE(nSidesPerBCNameVisu_FV(1:nBCNamesVisu))
mapAllBCSidesToDGBCSides = 0
mapAllBCSidesToFVBCSides = 0
nSidesPerBCNameVisu_DG = 0
nSidesPerBCNameVisu_FV = 0
nBCSidesVisu_DG = 0
nBCSidesVisu_FV = 0
DO iBC=1,nBCNamesTotal    ! iterate over all bc names
  IF (mapAllBCNamesToVisuBCNames(iBC).GT.0) THEN 
    DO iSide=1,nBCSides   ! iterate over all bc sides 
      IF (STRICMP(BoundaryName(BC(iSide)),BoundaryNamesTotal(iBC))) THEN ! check if side is of specific boundary name
        iElem = SideToElem(S2E_ELEM_ID,iSide)
        IF (FV_Elems(iElem).EQ.0)  THEN ! DG element
          nBCSidesVisu_DG = nBCSidesVisu_DG + 1
          mapAllBCSidesToDGBCSides(iSide) = nBCSidesVisu_DG
          nSidesPerBCNameVisu_DG(mapAllBCNamesToVisuBCNames(iBC)) = nSidesPerBCNameVisu_DG(mapAllBCNamesToVisuBCNames(iBC)) + 1
        ELSE ! FV Element
          nBCSidesVisu_FV = nBCSidesVisu_FV + 1
          mapAllBCSidesToFVBCSides(iSide) = nBCSidesVisu_FV
          nSidesPerBCNameVisu_FV(mapAllBCNamesToVisuBCNames(iBC)) = nSidesPerBCNameVisu_FV(mapAllBCNamesToVisuBCNames(iBC)) + 1
        END IF
      END IF
    END DO
  END IF
END DO

END SUBROUTINE Build_mapBCSides

END MODULE MOD_Posti_Mappings
