      SUBROUTINE DQAGP(F,A,B,NPTS2,POINTS,EPSABS,EPSREL,RESULT,ABSERR,
     *   NEVAL,IER,LENIW,LENW,LAST,IWORK,WORK)
C***BEGIN PROLOGUE  DQAGP
C***DATE WRITTEN   800101   (YYMMDD)
C***REVISION DATE  830518   (YYMMDD)
C***CATEGORY NO.  H2A2A1
C***KEYWORDS  AUTOMATIC INTEGRATOR, GENERAL-PURPOSE,
C             SINGULARITIES AT USER SPECIFIED POINTS,
C             EXTRAPOLATION, GLOBALLY ADAPTIVE
C***AUTHOR  PIESSENS,ROBERT,APPL. MATH. & PROGR. DIV - K.U.LEUVEN
C           DE DONCKER,ELISE,APPL. MATH. & PROGR. DIV. - K.U.LEUVEN
C***PURPOSE  THE ROUTINE CALCULATES AN APPROXIMATION RESULT TO A GIVEN
C            DEFINITE INTEGRAL I = INTEGRAL OF F OVER (A,B),
C            HOPEFULLY SATISFYING FOLLOWING CLAIM FOR ACCURACY
C            BREAK POINTS OF THE INTEGRATION INTERVAL, WHERE LOCAL
C            DIFFICULTIES OF THE INTEGRAND MAY OCCUR (E.G.
C            SINGULARITIES, DISCONTINUITIES), ARE PROVIDED BY THE USER.
C***DESCRIPTION
C
C        COMPUTATION OF A DEFINITE INTEGRAL
C        STANDARD FORTRAN SUBROUTINE
C        DOUBLE PRECISION VERSION
C
C        PARAMETERS
C         ON ENTRY
C            F      - SUBROUTINE F(X,IERR,RESULT) DEFINING THE INTEGRAND
C                     FUNCTION F(X). THE ACTUAL NAME FOR F NEEDS TO BE
C                     DECLARED E X T E R N A L IN THE DRIVER PROGRAM.
C
C            A      - DOUBLE PRECISION
C                     LOWER LIMIT OF INTEGRATION
C
C            B      - DOUBLE PRECISION
C                     UPPER LIMIT OF INTEGRATION
C
C            NPTS2  - INTEGER
C                     NUMBER EQUAL TO TWO MORE THAN THE NUMBER OF
C                     USER-SUPPLIED BREAK POINTS WITHIN THE INTEGRATION
C                     RANGE, NPTS.GE.2.
C                     IF NPTS2.LT.2, THE ROUTINE WILL END WITH IER = 6.
C
C            POINTS - DOUBLE PRECISION
C                     VECTOR OF DIMENSION NPTS2, THE FIRST (NPTS2-2)
C                     ELEMENTS OF WHICH ARE THE USER PROVIDED BREAK
C                     POINTS. IF THESE POINTS DO NOT CONSTITUTE AN
C                     ASCENDING SEQUENCE THERE WILL BE AN AUTOMATIC
C                     SORTING.
C
C            EPSABS - DOUBLE PRECISION
C                     ABSOLUTE ACCURACY REQUESTED
C            EPSREL - DOUBLE PRECISION
C                     RELATIVE ACCURACY REQUESTED
C                     IF  EPSABS.LE.0
C                     AND EPSREL.LT.MAX(50*REL.MACH.ACC.,0.5D-28),
C                     THE ROUTINE WILL END WITH IER = 6.
C
C         ON RETURN
C            RESULT - DOUBLE PRECISION
C                     APPROXIMATION TO THE INTEGRAL
C
C            ABSERR - DOUBLE PRECISION
C                     ESTIMATE OF THE MODULUS OF THE ABSOLUTE ERROR,
C                     WHICH SHOULD EQUAL OR EXCEED ABS(I-RESULT)
C
C            NEVAL  - INTEGER
C                     NUMBER OF INTEGRAND EVALUATIONS
C
C            IER    - INTEGER
C                     IER = 0 NORMAL AND RELIABLE TERMINATION OF THE
C                             ROUTINE. IT IS ASSUMED THAT THE REQUESTED
C                             ACCURACY HAS BEEN ACHIEVED.
C                     IER.GT.0 ABNORMAL TERMINATION OF THE ROUTINE.
C                             THE ESTIMATES FOR INTEGRAL AND ERROR ARE
C                             LESS RELIABLE. IT IS ASSUMED THAT THE
C                             REQUESTED ACCURACY HAS NOT BEEN ACHIEVED.
C            ERROR MESSAGES
C                     IER = 1 MAXIMUM NUMBER OF SUBDIVISIONS ALLOWED
C                             HAS BEEN ACHIEVED. ONE CAN ALLOW MORE
C                             SUBDIVISIONS BY INCREASING THE VALUE OF
C                             LIMIT (AND TAKING THE ACCORDING DIMENSION
C                             ADJUSTMENTS INTO ACCOUNT). HOWEVER, IF
C                             THIS YIELDS NO IMPROVEMENT IT IS ADVISED
C                             TO ANALYZE THE INTEGRAND IN ORDER TO
C                             DETERMINE THE INTEGRATION DIFFICULTIES. IF
C                             THE POSITION OF A LOCAL DIFFICULTY CAN BE
C                             DETERMINED (I.E. SINGULARITY,
C                             DISCONTINUITY WITHIN THE INTERVAL), IT
C                             SHOULD BE SUPPLIED TO THE ROUTINE AS AN
C                             ELEMENT OF THE VECTOR POINTS. IF NECESSARY
C                             AN APPROPRIATE SPECIAL-PURPOSE INTEGRATOR
C                             MUST BE USED, WHICH IS DESIGNED FOR
C                             HANDLING THE TYPE OF DIFFICULTY INVOLVED.
C                         = 2 THE OCCURRENCE OF ROUNDOFF ERROR IS
C                             DETECTED, WHICH PREVENTS THE REQUESTED
C                             TOLERANCE FROM BEING ACHIEVED.
C                             THE ERROR MAY BE UNDER-ESTIMATED.
C                         = 3 EXTREMELY BAD INTEGRAND BEHAVIOUR OCCURS
C                             AT SOME POINTS OF THE INTEGRATION
C                             INTERVAL.
C                         = 4 THE ALGORITHM DOES NOT CONVERGE.
C                             ROUNDOFF ERROR IS DETECTED IN THE
C                             EXTRAPOLATION TABLE.
C                             IT IS PRESUMED THAT THE REQUESTED
C                             TOLERANCE CANNOT BE ACHIEVED, AND THAT
C                             THE RETURNED RESULT IS THE BEST WHICH
C                             CAN BE OBTAINED.
C                         = 5 THE INTEGRAL IS PROBABLY DIVERGENT, OR
C                             SLOWLY CONVERGENT. IT MUST BE NOTED THAT
C                             DIVERGENCE CAN OCCUR WITH ANY OTHER VALUE
C                             OF IER.GT.0.
C                         = 6 THE INPUT IS INVALID BECAUSE
C                             NPTS2.LT.2 OR
C                             BREAK POINTS ARE SPECIFIED OUTSIDE
C                             THE INTEGRATION RANGE OR
C                             (EPSABS.LE.0 AND
C                              EPSREL.LT.MAX(50*REL.MACH.ACC.,0.5D-28))
C                             RESULT, ABSERR, NEVAL, LAST ARE SET TO
C                             ZERO. EXEPT WHEN LENIW OR LENW OR NPTS2 IS
C                             INVALID, IWORK(1), IWORK(LIMIT+1),
C                             WORK(LIMIT*2+1) AND WORK(LIMIT*3+1)
C                             ARE SET TO ZERO.
C                             WORK(1) IS SET TO A AND WORK(LIMIT+1)
C                             TO B (WHERE LIMIT = (LENIW-NPTS2)/2).
C
C         DIMENSIONING PARAMETERS
C            LENIW - INTEGER
C                    DIMENSIONING PARAMETER FOR IWORK
C                    LENIW DETERMINES LIMIT = (LENIW-NPTS2)/2,
C                    WHICH IS THE MAXIMUM NUMBER OF SUBINTERVALS IN THE
C                    PARTITION OF THE GIVEN INTEGRATION INTERVAL (A,B),
C                    LENIW.GE.(3*NPTS2-2).
C                    IF LENIW.LT.(3*NPTS2-2), THE ROUTINE WILL END WITH
C                    IER = 6.
C
C            LENW  - INTEGER
C                    DIMENSIONING PARAMETER FOR WORK
C                    LENW MUST BE AT LEAST LENIW*2-NPTS2.
C                    IF LENW.LT.LENIW*2-NPTS2, THE ROUTINE WILL END
C                    WITH IER = 6.
C
C            LAST  - INTEGER
C                    ON RETURN, LAST EQUALS THE NUMBER OF SUBINTERVALS
C                    PRODUCED IN THE SUBDIVISION PROCESS, WHICH
C                    DETERMINES THE NUMBER OF SIGNIFICANT ELEMENTS
C                    ACTUALLY IN THE WORK ARRAYS.
C
C         WORK ARRAYS
C            IWORK - INTEGER
C                    VECTOR OF DIMENSION AT LEAST LENIW. ON RETURN,
C                    THE FIRST K ELEMENTS OF WHICH CONTAIN
C                    POINTERS TO THE ERROR ESTIMATES OVER THE
C                    SUBINTERVALS, SUCH THAT WORK(LIMIT*3+IWORK(1)),...,
C                    WORK(LIMIT*3+IWORK(K)) FORM A DECREASING
C                    SEQUENCE, WITH K = LAST IF LAST.LE.(LIMIT/2+2), AND
C                    K = LIMIT+1-LAST OTHERWISE
C                    IWORK(LIMIT+1), ...,IWORK(LIMIT+LAST) CONTAIN THE
C                     SUBDIVISION LEVELS OF THE SUBINTERVALS, I.E.
C                     IF (AA,BB) IS A SUBINTERVAL OF (P1,P2)
C                     WHERE P1 AS WELL AS P2 IS A USER-PROVIDED
C                     BREAK POINT OR INTEGRATION LIMIT, THEN (AA,BB) HAS
C                     LEVEL L IF ABS(BB-AA) = ABS(P2-P1)*2**(-L),
C                    IWORK(LIMIT*2+1), ..., IWORK(LIMIT*2+NPTS2) HAVE
C                     NO SIGNIFICANCE FOR THE USER,
C                    NOTE THAT LIMIT = (LENIW-NPTS2)/2.
C
C            WORK  - DOUBLE PRECISION
C                    VECTOR OF DIMENSION AT LEAST LENW
C                    ON RETURN
C                    WORK(1), ..., WORK(LAST) CONTAIN THE LEFT
C                     END POINTS OF THE SUBINTERVALS IN THE
C                     PARTITION OF (A,B),
C                    WORK(LIMIT+1), ..., WORK(LIMIT+LAST) CONTAIN
C                     THE RIGHT END POINTS,
C                    WORK(LIMIT*2+1), ..., WORK(LIMIT*2+LAST) CONTAIN
C                     THE INTEGRAL APPROXIMATIONS OVER THE SUBINTERVALS,
C                    WORK(LIMIT*3+1), ..., WORK(LIMIT*3+LAST)
C                     CONTAIN THE CORRESPONDING ERROR ESTIMATES,
C                    WORK(LIMIT*4+1), ..., WORK(LIMIT*4+NPTS2)
C                     CONTAIN THE INTEGRATION LIMITS AND THE
C                     BREAK POINTS SORTED IN AN ASCENDING SEQUENCE.
C                    NOTE THAT LIMIT = (LENIW-NPTS2)/2.
C
C***REFERENCES  (NONE)
C***ROUTINES CALLED  DQAGPE,XERROR
C***END PROLOGUE  DQAGP
C
      DOUBLE PRECISION A,ABSERR,B,EPSABS,EPSREL,F,POINTS,RESULT,WORK
      INTEGER IER,IWORK,LAST,LENIW,LENW,LIMIT,LVL,L1,L2,L3,L4,NEVAL,
     *  NPTS2
C
      DIMENSION IWORK(LENIW),POINTS(NPTS2),WORK(LENW)
C
      EXTERNAL F
C
C         CHECK VALIDITY OF LIMIT AND LENW.
C
C***FIRST EXECUTABLE STATEMENT  DQAGP
      IER = 6
      NEVAL = 0
      LAST = 0
      RESULT = 0.0D+00
      ABSERR = 0.0D+00
      IF(LENIW.LT.(3*NPTS2-2).OR.LENW.LT.(LENIW*2-NPTS2).OR.NPTS2.LT.2)
     *  GO TO 10
C
C         PREPARE CALL FOR DQAGPE.
C
      LIMIT = (LENIW-NPTS2)/2
      L1 = LIMIT+1
      L2 = LIMIT+L1
      L3 = LIMIT+L2
      L4 = LIMIT+L3
C
      CALL DQAGPE(F,A,B,NPTS2,POINTS,EPSABS,EPSREL,LIMIT,RESULT,ABSERR,
     *  NEVAL,IER,WORK(1),WORK(L1),WORK(L2),WORK(L3),WORK(L4),
     *  IWORK(1),IWORK(L1),IWORK(L2),LAST)
C
C         CALL ERROR HANDLER IF NECESSARY.
C
      LVL = 0
10    IF(IER.EQ.6) LVL = 1
      IF(IER.GT.0) CALL XERROR(26HABNORMAL RETURN FROM DQAGP,26,IER,LVL)
      RETURN
      END
