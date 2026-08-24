!     ==================================================================
!     GEOSAT TELEMETRY PROCESSOR
!     SPACE VEHICLE 42 -- COMMAND AND TELEMETRY GROUND SEGMENT
!
!     ORIGINAL AUTHOR : R. HALVORSEN, GROUND SYSTEMS BRANCH   1987-03
!     PORTED VAX/VMS -> ALPHA/OSF                             1994-08
!     Y2K WINDOWING PATCH, MEMO GS-98-441                     1998-11
!     THERMISTOR FIT REVISED, ECO 91-217                      1991-06
!     MAINTAINED BY   : (VACANT)
!
!     THIS DECK CONTAINS THE ENTIRE FLIGHT TELEMETRY PROCESSING CHAIN.
!     IT WAS DELIVERED AS A SINGLE COMPILATION UNIT BECAUSE THE
!     ORIGINAL VMS BUILD PROCEDURE COULD NOT RESOLVE THE OVERLAY
!     SEGMENTS OTHERWISE (SEE MEMO GS-89-112).  IT HAS NEVER BEEN
!     SPLIT.
!
!     BUILD:  make
!     RUN:    ./build/geosat < tests/golden/pass01.tlm
!     ==================================================================

!     ==================================================================
!     GEOSAT TELEMETRY PROCESSOR -- MAIN DRIVER
!
!     READS HEX ENCODED TELEMETRY FRAMES FROM STANDARD INPUT, DECOMS
!     EACH FRAME, CONVERTS TO ENGINEERING UNITS, SCREENS AGAINST THE
!     ON ORBIT LIMIT SET, PROPAGATES A QUICK LOOK SUBSATELLITE POINT,
!     AND WRITES A PASS SUMMARY TO STANDARD OUTPUT.
!
!     BUILD:  make            (see legacy/Makefile)
!     RUN:    ./geosat < tests/golden/pass01.tlm
!
!     THIS PROGRAM HAS NO NETWORK, FILESYSTEM, OR CLOCK DEPENDENCIES.
!     GIVEN THE SAME INPUT IT PRODUCES BYTE IDENTICAL OUTPUT.  THAT
!     PROPERTY IS WHAT MAKES THE CHARACTERIZATION TEST SUITE POSSIBLE.
!     ==================================================================
      PROGRAM GEOSAT
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER IRC
      INTEGER DRC

      NGOOD  = 0
      NBADCR = 0
      NBADSY = 0
      NALARM = 0

  10  CONTINUE

         CALL RDFRM(5, IRC)

         IF (IRC .EQ. 1) GO TO 800
         IF (IRC .EQ. 2) THEN
            WRITE (6, 950)
            GO TO 10
         END IF

         CALL TLMDEC(DRC)

         IF (DRC .EQ. 1) THEN
            NBADSY = NBADSY + 1
            WRITE (6, 951)
            GO TO 10
         END IF

         IF (DRC .EQ. 2) THEN
            NBADCR = NBADCR + 1
            WRITE (6, 952) FRMCNT
            GO TO 10
         END IF

         NGOOD = NGOOD + 1

         CALL ENGCNV
         CALL LIMCHK
         CALL TIMCNV(GPSSEC)
         CALL ORBPRP(GPSSEC)
         CALL REPORT(6)

      GO TO 10

  800 CONTINUE

      WRITE (6, 960)
      WRITE (6, 961) NGOOD
      WRITE (6, 962) NBADSY
      WRITE (6, 963) NBADCR
      WRITE (6, 964) NALARM

      STOP

  950 FORMAT ('*** MALFORMED RECORD SKIPPED')
  951 FORMAT ('*** SYNC LOSS')
  952 FORMAT ('*** CRC FAILURE ON FRAME ', I10)
  960 FORMAT ('---- PASS SUMMARY ----')
  961 FORMAT ('FRAMES PROCESSED  ', I8)
  962 FORMAT ('SYNC LOSSES       ', I8)
  963 FORMAT ('CRC FAILURES      ', I8)
  964 FORMAT ('LIMIT VIOLATIONS  ', I8)

      END
!     ==================================================================
!     RDFRM -- READ ONE HEX ENCODED FRAME RECORD FROM UNIT LUN
!
!     THE DECOM FRONT END WRITES ONE FRAME PER RECORD AS 64 ASCII HEX
!     CHARACTERS, UPPER CASE, NO SEPARATORS.  BLANK RECORDS AND RECORDS
!     BEGINNING WITH AN ASTERISK ARE TREATED AS OPERATOR COMMENTS AND
!     SKIPPED (THIS BEHAVIOUR IS RELIED ON BY THE PASS LOG FORMAT).
!
!     IRC   0 = FRAME READ
!           1 = END OF FILE
!           2 = MALFORMED RECORD
!     ==================================================================
      SUBROUTINE RDFRM(LUN, IRC)
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER LUN
      INTEGER IRC

      CHARACTER*80 LINE
      INTEGER I
      INTEGER HI
      INTEGER LO
      INTEGER HEXVAL
      EXTERNAL HEXVAL

  10  CONTINUE
      READ (LUN, '(A80)', END=900) LINE

      IF (LINE(1:1) .EQ. '*') GO TO 10
      IF (LINE(1:2) .EQ. '  ') GO TO 10

      DO 100 I = 1, FRMLEN
         HI = HEXVAL(LINE(2*I-1 : 2*I-1))
         LO = HEXVAL(LINE(2*I   : 2*I  ))
         IF (HI .LT. 0 .OR. LO .LT. 0) THEN
            IRC = 2
            RETURN
         END IF
         FRMBUF(I) = HI * 16 + LO
  100 CONTINUE

      IRC = 0
      RETURN

  900 CONTINUE
      IRC = 1
      RETURN
      END


!     ==================================================================
!     HEXVAL -- SINGLE HEX CHARACTER TO INTEGER, -1 IF INVALID
!     ==================================================================
      INTEGER FUNCTION HEXVAL(C)
      IMPLICIT NONE

      CHARACTER*1 C
      INTEGER N

      N = ICHAR(C)

      IF (N .GE. 48 .AND. N .LE. 57) THEN
         HEXVAL = N - 48
      ELSE IF (N .GE. 65 .AND. N .LE. 70) THEN
         HEXVAL = N - 55
      ELSE IF (N .GE. 97 .AND. N .LE. 102) THEN
         HEXVAL = N - 87
      ELSE
         HEXVAL = -1
      END IF

      RETURN
      END
!     ==================================================================
!     TLMDEC -- DECOMMUTATE ONE 32 BYTE TELEMETRY FRAME
!
!     UNPACKS THE PRIMARY HEADER AND THE ELEVEN ANALOG CHANNELS FROM
!     /FRAME/ INTO /TLMDAT/.  FRAME LAYOUT IS ICD 4021-B TABLE 6-2:
!
!       BYTE  1- 2   SYNC PATTERN 1ACF
!       BYTE  3      SPACECRAFT ID
!       BYTE  4      APPLICATION PROCESS ID
!       BYTE  5- 8   FRAME COUNTER, UNSIGNED, BIG ENDIAN
!       BYTE  9-12   GPS SECONDS OF EPOCH, UNSIGNED, BIG ENDIAN
!       BYTE 13-14   CH 1  BUS VOLTAGE          UNSIGNED
!       BYTE 15-16   CH 2  BUS CURRENT          UNSIGNED
!       BYTE 17-18   CH 3  BATTERY TEMPERATURE  UNSIGNED
!       BYTE 19-20   CH 4  REACTION WHEEL RPM   SIGNED
!       BYTE 21-22   CH 5  GYRO X RATE          SIGNED
!       BYTE 23-24   CH 6  GYRO Y RATE          SIGNED
!       BYTE 25-26   CH 7  GYRO Z RATE          SIGNED
!       BYTE 27-28   CH 8  PAYLOAD TEMPERATURE  UNSIGNED
!       BYTE 29      CH 9  TRANSMITTER POWER    UNSIGNED, 8 BIT
!       BYTE 30      CH10  RECEIVER AGC         UNSIGNED, 8 BIT
!                    CH11  SOLAR ARRAY ANGLE IS DERIVED, NOT DECOMMED
!       BYTE 31-32   CRC-16
!
!     IRC RETURN CODES  0 = GOOD
!                       1 = SYNC PATTERN MISMATCH
!                       2 = CRC MISMATCH
!     ==================================================================
      SUBROUTINE TLMDEC(IRC)
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER IRC

      INTEGER CRCCHK
      EXTERNAL CRCCHK

      INTEGER SYNC
      INTEGER CRCRD
      INTEGER CRCCM
      INTEGER I

      IRC = 0

!     ---- SYNC PATTERN ------------------------------------------------
      SYNC = FRMBUF(1) * 256 + FRMBUF(2)
      IF (SYNC .NE. SYNCW) THEN
         IRC = 1
         RETURN
      END IF

!     ---- CRC ---------------------------------------------------------
      CRCRD = FRMBUF(31) * 256 + FRMBUF(32)
      CRCCM = CRCCHK(FRMBUF, 30)
      IF (CRCRD .NE. CRCCM) THEN
         IRC = 2
         RETURN
      END IF

!     ---- PRIMARY HEADER ----------------------------------------------
      SCID = FRMBUF(3)
      APID = FRMBUF(4)

      FRMCNT = ((FRMBUF(5)  * 256 + FRMBUF(6))  * 256
     +           + FRMBUF(7)) * 256 + FRMBUF(8)

      GPSSEC = ((FRMBUF(9)  * 256 + FRMBUF(10)) * 256
     +           + FRMBUF(11)) * 256 + FRMBUF(12)

!     ---- ANALOG CHANNELS ---------------------------------------------
      DO 100 I = 1, MAXCHN
         RAWVAL(I) = 0
  100 CONTINUE

      RAWVAL(1) = FRMBUF(13) * 256 + FRMBUF(14)
      RAWVAL(2) = FRMBUF(15) * 256 + FRMBUF(16)
      RAWVAL(3) = FRMBUF(17) * 256 + FRMBUF(18)

      RAWVAL(4) = FRMBUF(19) * 256 + FRMBUF(20)
      IF (RAWVAL(4) .GT. 32767) RAWVAL(4) = RAWVAL(4) - 65536

      RAWVAL(5) = FRMBUF(21) * 256 + FRMBUF(22)
      IF (RAWVAL(5) .GT. 32767) RAWVAL(5) = RAWVAL(5) - 65536

      RAWVAL(6) = FRMBUF(23) * 256 + FRMBUF(24)
      IF (RAWVAL(6) .GT. 32767) RAWVAL(6) = RAWVAL(6) - 65536

      RAWVAL(7) = FRMBUF(25) * 256 + FRMBUF(26)
      IF (RAWVAL(7) .GT. 32767) RAWVAL(7) = RAWVAL(7) - 65536

      RAWVAL(8)  = FRMBUF(27) * 256 + FRMBUF(28)
      RAWVAL(9)  = FRMBUF(29)
      RAWVAL(10) = FRMBUF(30)

!     CH11 SOLAR ARRAY ANGLE IS RECONSTRUCTED FROM THE PAYLOAD STATUS
!     BITS IN THE LOW NIBBLE OF BYTE 28.  SEE ECO 91-217.
      RAWVAL(11) = IAND(FRMBUF(28), 15) * 24

      RETURN
      END
!     ==================================================================
!     CRCCHK -- CCITT CRC-16 OVER THE FIRST N BYTES OF THE FRAME
!
!     POLYNOMIAL 1021 HEX, INITIAL VALUE FFFF HEX, NO FINAL XOR.
!     PER ICD 4021-B SECTION 6.7.  THE ORIGINAL IMPLEMENTATION USED
!     A 256 ENTRY LOOKUP TABLE BUT THE TABLE WAS LOST IN THE 1994
!     VAX TO ALPHA PORT, SO THIS IS THE BIT SERIAL VERSION.
!     ==================================================================
      INTEGER FUNCTION CRCCHK(BUF, N)
      IMPLICIT NONE

      INTEGER BUF(*)
      INTEGER N

      INTEGER CRC
      INTEGER I
      INTEGER J
      INTEGER B
      INTEGER MSB

      CRC = 65535

      DO 200 I = 1, N
         B = BUF(I)
         IF (B .LT. 0) B = B + 256
!        FOLD THE BYTE INTO THE HIGH ORDER HALF OF THE REGISTER
         CRC = IEOR(CRC, ISHFT(B, 8))
         IF (CRC .GT. 65535) CRC = IAND(CRC, 65535)

         DO 100 J = 1, 8
            MSB = IAND(CRC, 32768)
            CRC = IAND(ISHFT(CRC, 1), 65535)
            IF (MSB .NE. 0) THEN
               CRC = IEOR(CRC, 4129)
            END IF
  100    CONTINUE
  200 CONTINUE

      CRCCHK = IAND(CRC, 65535)

      RETURN
      END
!     ==================================================================
!     ENGCNV -- RAW COUNTS TO ENGINEERING UNITS
!
!     APPLIES A SECOND ORDER POLYNOMIAL PER CHANNEL:
!
!         EU = C0 + C1*RAW + C2*RAW*RAW
!
!     COEFFICIENTS ARE THE FLIGHT CALIBRATION SET FROM THE 1986
!     THERMAL VACUUM CAMPAIGN, TRANSCRIBED FROM CAL REPORT TV-86-09.
!     CHANNEL 3 (BATTERY TEMPERATURE) USES THE REVISED THERMISTOR
!     FIT FROM ECO 91-217 -- THE ORIGINAL LINEAR FIT WAS 4 DEG C HIGH
!     AT THE COLD END AND CAUSED SPURIOUS RED ALARMS DURING ECLIPSE.
!     ==================================================================
      SUBROUTINE ENGCNV
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      REAL C0(MAXCHN)
      REAL C1(MAXCHN)
      REAL C2(MAXCHN)
      INTEGER I
      REAL    R

!     ---- OFFSET TERM  CH1 THROUGH CH11 -------------------------------
      DATA C0 / 0.0, 0.0, -55.0, 0.0, 0.0, 0.0,
     +          0.0, -40.0, 0.0, -120.0, 0.0 /

!     ---- LINEAR TERM  CH1 THROUGH CH11 -------------------------------
      DATA C1 / 0.0012207, 0.0003052, 0.0025400, 0.5000000,
     +          0.0019531, 0.0019531, 0.0019531, 0.0030518,
     +          0.0392157, 0.4705882, 1.0000000 /

!     ---- QUADRATIC TERM  CH1 THROUGH CH11 ----------------------------
      DATA C2 / 0.0, 0.0, -1.2E-8, 0.0, 0.0, 0.0,
     +          0.0, 0.0, 0.0, 0.0, 0.0 /

      DO 100 I = 1, MAXCHN
         R = REAL(RAWVAL(I))
         ENGVAL(I) = C0(I) + C1(I) * R + C2(I) * R * R
  100 CONTINUE

!     SOLAR ARRAY ANGLE IS ALREADY IN DEGREES AND WRAPS AT 360
      IF (ENGVAL(11) .GE. 360.0) THEN
         ENGVAL(11) = ENGVAL(11) - 360.0
      END IF

      RETURN
      END
!     ==================================================================
!     LIMCHK -- RED AND YELLOW LIMIT SCREENING
!
!     LIMIT SET IS THE ON ORBIT SET FROM THE FLIGHT OPERATIONS HANDBOOK
!     FOH-4021 REV C, TABLE 5-3.  CHANNELS WITH NO MEANINGFUL LIMITS
!     (CH 9, CH 11) ARE GIVEN WIDE OPEN VALUES RATHER THAN BEING
!     SPECIAL CASED, BECAUSE THE ORIGINAL DISPLAY DRIVER INDEXED THIS
!     TABLE DIRECTLY AND WOULD FAULT ON A SHORT TABLE.
!
!     ALMSTS  0 = OK
!             1 = YELLOW LOW      2 = YELLOW HIGH
!             3 = RED LOW         4 = RED HIGH
!     ==================================================================
      SUBROUTINE LIMCHK
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      REAL RL(MAXCHN)
      REAL YL(MAXCHN)
      REAL YH(MAXCHN)
      REAL RH(MAXCHN)

!     ---- RED LOW -----------------------------------------------------
      DATA RL /  24.0,   0.0, -20.0, -6000.0,  -8.0,  -8.0,  -8.0,
     +          -30.0,   0.0, -95.0,   0.0 /
!     ---- YELLOW LOW --------------------------------------------------
      DATA YL /  26.0,   0.5, -10.0, -5000.0,  -5.0,  -5.0,  -5.0,
     +          -20.0,   1.0, -90.0,   0.0 /
!     ---- YELLOW HIGH -------------------------------------------------
      DATA YH /  32.5,  14.0,  35.0,  5000.0,   5.0,   5.0,   5.0,
     +           45.0,   9.0, -55.0, 360.0 /
!     ---- RED HIGH ----------------------------------------------------
      DATA RH /  34.0,  16.0,  45.0,  6000.0,   8.0,   8.0,   8.0,
     +           55.0,  10.0, -45.0, 360.0 /

      INTEGER I
      REAL    V

      DO 100 I = 1, MAXCHN
         V = ENGVAL(I)
         ALMSTS(I) = 0

         IF (V .LT. RL(I)) THEN
            ALMSTS(I) = 3
         ELSE IF (V .GT. RH(I)) THEN
            ALMSTS(I) = 4
         ELSE IF (V .LT. YL(I)) THEN
            ALMSTS(I) = 1
         ELSE IF (V .GT. YH(I)) THEN
            ALMSTS(I) = 2
         END IF

         IF (ALMSTS(I) .NE. 0) NALARM = NALARM + 1
  100 CONTINUE

      RETURN
      END
!     ==================================================================
!     TIMCNV -- GPS SECONDS OF EPOCH TO UTC CALENDAR FIELDS
!
!     GPS EPOCH IS 1980 JAN 06 00:00:00 UTC.  LEAP SECOND OFFSET IS
!     CARRIED IN THE DATA STATEMENT BELOW AND MUST BE HAND EDITED WHEN
!     IERS ANNOUNCES A NEW LEAP SECOND.  LAST UPDATED 2016-12-31 (18).
!
!     NOTE - THE 1998 Y2K PATCH (MEMO GS-98-441) LEFT THE TWO DIGIT
!     YEAR IN /TIMBLK/ FOR THE BENEFIT OF THE STRIP CHART RECORDER
!     DRIVER.  UTCYR IS THE FULL FOUR DIGIT YEAR.  DO NOT "FIX" THIS
!     WITHOUT CHECKING RTDISP.
!     ==================================================================
      SUBROUTINE TIMCNV(GSEC)
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER GSEC

      INTEGER LEAPS
      DATA    LEAPS /18/

      INTEGER MDAYS(12)
      DATA    MDAYS /31,28,31,30,31,30,31,31,30,31,30,31/

      INTEGER TOTSEC
      INTEGER NDAYS
      INTEGER REM
      INTEGER YR
      INTEGER DINY
      INTEGER MO
      INTEGER DIM

!     BACK OUT LEAP SECONDS TO REACH UTC
      TOTSEC = GSEC - LEAPS

      NDAYS = TOTSEC / 86400
      REM   = TOTSEC - (NDAYS * 86400)
      IF (REM .LT. 0) THEN
         REM   = REM + 86400
         NDAYS = NDAYS - 1
      END IF

      UTCHR  = REM / 3600
      UTCMIN = (REM - UTCHR * 3600) / 60
      UTCSEC = REM - UTCHR * 3600 - UTCMIN * 60

!     WALK FORWARD FROM THE GPS EPOCH, 1980 JAN 06
      YR    = 1980
      NDAYS = NDAYS + 5

  100 CONTINUE
         DINY = 365
         IF (MOD(YR,4) .EQ. 0 .AND. MOD(YR,100) .NE. 0) DINY = 366
         IF (MOD(YR,400) .EQ. 0) DINY = 366
         IF (NDAYS .LT. DINY) GO TO 200
         NDAYS = NDAYS - DINY
         YR = YR + 1
      GO TO 100

  200 CONTINUE
      UTCYR  = YR
      UTCDOY = NDAYS + 1

      MO = 1
  300 CONTINUE
         DIM = MDAYS(MO)
         IF (MO .EQ. 2) THEN
            IF (MOD(YR,4) .EQ. 0 .AND. MOD(YR,100) .NE. 0) DIM = 29
            IF (MOD(YR,400) .EQ. 0) DIM = 29
         END IF
         IF (NDAYS .LT. DIM) GO TO 400
         NDAYS = NDAYS - DIM
         MO = MO + 1
      GO TO 300

  400 CONTINUE
      UTCMON = MO
      UTCDAY = NDAYS + 1

      RETURN
      END
!     ==================================================================
!     ORBPRP -- SUBSATELLITE POINT FROM A CIRCULAR ORBIT MODEL
!
!     THIS IS THE "QUICK LOOK" PROPAGATOR ONLY.  IT ASSUMES A CIRCULAR
!     ORBIT AT THE NOMINAL MISSION ALTITUDE AND IGNORES J2, DRAG, AND
!     ALL MANEUVER HISTORY.  THE PRECISION EPHEMERIS IS PRODUCED BY THE
!     FDF AND DELIVERED SEPARATELY; DO NOT USE THIS ROUTINE FOR ANY
!     POINTING OR CONJUNCTION PRODUCT.  SEE MEMO GS-89-112.
!
!     ELEMENTS ARE FROZEN AT THE EPOCH BELOW BECAUSE THE ELEMENT
!     LOADER WAS NEVER PORTED OFF THE VAX.
!     ==================================================================
      SUBROUTINE ORBPRP(GSEC)
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER GSEC

      REAL PI
      PARAMETER (PI = 3.14159265)

      REAL RE
      PARAMETER (RE = 6378.137)

!     ---- FROZEN ELEMENT SET, EPOCH GPS SECOND 630720000 --------------
      REAL ELALT
      PARAMETER (ELALT = 785.0)
      REAL ELINC
      PARAMETER (ELINC = 98.6)
      REAL ELRAAN
      PARAMETER (ELRAAN = 142.35)
      INTEGER ELEPOC
      PARAMETER (ELEPOC = 630720000)

      REAL    A
      REAL    PERIOD
      REAL    DT
      REAL    U
      REAL    SINI
      REAL    ARGLAT
      REAL    LONASC
      REAL    XLAT
      REAL    XLON
      REAL    RATE

      A = RE + ELALT

!     KEPLERIAN PERIOD, MU = 398600.4418 KM3/S2
      PERIOD = 2.0 * PI * SQRT((A * A * A) / 398600.4418)

      DT = REAL(GSEC - ELEPOC)

!     ARGUMENT OF LATITUDE, RADIANS
      U = 2.0 * PI * (DT / PERIOD)
      ARGLAT = AMOD(U, 2.0 * PI)

      SINI = SIN(ELINC * PI / 180.0)

!     GEODETIC LATITUDE OF THE SUBSATELLITE POINT
      XLAT = ASIN(SINI * SIN(ARGLAT)) * 180.0 / PI

!     LONGITUDE OF THE ASCENDING NODE, ROTATED FOR EARTH SPIN
!     RATE IS 360.985647 DEG PER MEAN SOLAR DAY
      RATE   = 360.985647 / 86400.0
      LONASC = ELRAAN - RATE * DT

!     IN TRACK DISPLACEMENT FROM THE NODE
      XLON = LONASC + ATAN2(COS(ELINC * PI / 180.0) * SIN(ARGLAT),
     +                      COS(ARGLAT)) * 180.0 / PI

!     WRAP TO -180 .. +180
      XLON = AMOD(XLON, 360.0)
      IF (XLON .GT.  180.0) XLON = XLON - 360.0
      IF (XLON .LT. -180.0) XLON = XLON + 360.0

      SSLAT = XLAT
      SSLON = XLON
      SSALT = ELALT

      RETURN
      END
!     ==================================================================
!     REPORT -- FORMATTED PASS SUMMARY TO UNIT 6
!
!     THE COLUMN LAYOUT IS CONSUMED BY THE DOWNSTREAM ARCHIVE LOADER
!     (ARCLOD) WHICH PARSES BY FIXED COLUMN POSITION, NOT BY DELIMITER.
!     ANY CHANGE TO THESE FORMAT STATEMENTS BREAKS THE ARCHIVE.
!     ==================================================================
      SUBROUTINE REPORT(LUN)
      IMPLICIT NONE

      INCLUDE 'geosat.inc'

      INTEGER LUN

      CHARACTER*4 CHNAM(MAXCHN)
      CHARACTER*8 CHUNI(MAXCHN)
      CHARACTER*3 ASTAT(0:4)
      INTEGER I

      DATA CHNAM / 'BUSV', 'BUSI', 'BATT', 'RWRP', 'GYRX', 'GYRY',
     +             'GYRZ', 'PLTM', 'XMTP', 'RAGC', 'SAAN' /

      DATA CHUNI / 'VDC     ', 'AMPS    ', 'DEG C   ', 'RPM     ',
     +             'DEG/S   ', 'DEG/S   ', 'DEG/S   ', 'DEG C   ',
     +             'WATTS   ', 'DBM     ', 'DEG     ' /

      DATA ASTAT / ' OK', ' YL', ' YH', ' RL', ' RH' /

      WRITE (LUN, 900)
      WRITE (LUN, 901) SCID, APID, FRMCNT
      WRITE (LUN, 902) UTCYR, UTCMON, UTCDAY, UTCHR, UTCMIN, UTCSEC,
     +                 UTCDOY
      WRITE (LUN, 903) SSLAT, SSLON, SSALT
      WRITE (LUN, 904)

      DO 100 I = 1, MAXCHN
         WRITE (LUN, 905) I, CHNAM(I), RAWVAL(I), ENGVAL(I),
     +                    CHUNI(I), ASTAT(ALMSTS(I))
  100 CONTINUE

      RETURN

  900 FORMAT ('---- GEOSAT TELEMETRY FRAME ----')
  901 FORMAT ('SCID=', I3, '  APID=', I3, '  FRAME=', I10)
  902 FORMAT ('UTC ', I4.4, '-', I2.2, '-', I2.2, ' ', I2.2, ':',
     +        I2.2, ':', I2.2, '  DOY=', I3.3)
  903 FORMAT ('SSP LAT=', F8.3, '  LON=', F9.3, '  ALT=', F7.1)
  904 FORMAT ('CH NAME     RAW        EU  UNITS    ST')
  905 FORMAT (I2, 1X, A4, 1X, I7, 1X, F9.3, 1X, A8, 1X, A3)

      END
