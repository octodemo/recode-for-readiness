!     ==================================================================
!     GEOSAT TELEMETRY PROCESSOR -- GLOBAL COMMON BLOCK DEFINITIONS
!
!     ORIGINAL AUTHOR : R. HALVORSEN, GROUND SYSTEMS BRANCH   1987-03
!     MAINTAINED BY   : (VACANT)
!     LAST MODIFIED   : 1998-11-02  Y2K WINDOWING PATCH, MEMO GS-98-441
!
!     WARNING - THE LAYOUT OF /FRAME/ IS ASSUMED BY THE DECOM HARDWARE
!     INTERFACE IN TLMDEC.  DO NOT REORDER WITHOUT REGENERATING THE
!     DECOM TABLES (SEE ICD 4021-B SECTION 6.2).
!     ==================================================================

      INTEGER   MAXCHN
      PARAMETER (MAXCHN = 11)

      INTEGER   FRMLEN
      PARAMETER (FRMLEN = 32)

!     SYNC PATTERN 1ACF HEX -- SEE ICD 4021-B TABLE 6-1
      INTEGER   SYNCW
      PARAMETER (SYNCW = 6863)

!     ------------------------------------------------------------------
!     RAW FRAME BUFFER AND DECODED PRIMARY HEADER FIELDS
!     ------------------------------------------------------------------
      INTEGER   FRMBUF(FRMLEN)
      INTEGER   SCID
      INTEGER   APID
      INTEGER   FRMCNT
      INTEGER   GPSSEC
      COMMON /FRAME/ FRMBUF, SCID, APID, FRMCNT, GPSSEC

!     ------------------------------------------------------------------
!     RAW COUNTS, CONVERTED ENGINEERING UNITS, ALARM STATUS
!     ALMSTS: 0=OK 1=YELLOW LOW 2=YELLOW HIGH 3=RED LOW 4=RED HIGH
!     ------------------------------------------------------------------
      INTEGER   RAWVAL(MAXCHN)
      REAL      ENGVAL(MAXCHN)
      INTEGER   ALMSTS(MAXCHN)
      COMMON /TLMDAT/ RAWVAL, ENGVAL, ALMSTS

!     ------------------------------------------------------------------
!     DECODED UTC TIME FIELDS
!     ------------------------------------------------------------------
      INTEGER   UTCYR, UTCMON, UTCDAY, UTCHR, UTCMIN, UTCSEC, UTCDOY
      COMMON /TIMBLK/ UTCYR, UTCMON, UTCDAY, UTCHR, UTCMIN, UTCSEC,
     +                UTCDOY

!     ------------------------------------------------------------------
!     PROPAGATED SUBSATELLITE POINT
!     ------------------------------------------------------------------
      REAL      SSLAT, SSLON, SSALT
      COMMON /ORBBLK/ SSLAT, SSLON, SSALT

!     ------------------------------------------------------------------
!     RUN COUNTERS
!     ------------------------------------------------------------------
      INTEGER   NGOOD, NBADCR, NBADSY, NALARM
      COMMON /STATS/ NGOOD, NBADCR, NBADSY, NALARM
