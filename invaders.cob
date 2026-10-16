>>SOURCE FORMAT IS FREE
*> ================================================================
*>  INVADERS.COB  -  Space Invaders for the terminal, in GnuCOBOL
*>
*>  Build : cobc -x -O2 -o invaders invaders.cob
*>  Run   : ./invaders
*>          needs an 80x24 (or larger) UTF-8 terminal with 256 colours
*>
*>  Keys  : LEFT/RIGHT or A/D   move
*>          SPACE               fire
*>          P                   pause
*>          M                   sound on/off
*>          Q                   quit
*>
*>  Sound : sound effects are WAV files in ./sounds (make sounds),
*>          played in the background by the first of pw-play,
*>          paplay or aplay that is installed.  Run from the
*>          project directory; without the files the game is silent.
*>
*>  How it talks to the terminal
*>  ----------------------------
*>  GnuCOBOL's DISPLAY ... AT writes curses one byte at a time,
*>  which mangles UTF-8.  So this program drives the terminal
*>  itself:
*>    - tcgetattr/tcsetattr switch the tty to raw, non-blocking
*>      input, and read() polls the keyboard once per frame;
*>    - every frame is drawn into GRID, one UTF-8 character and one
*>      256-colour number per cell, turned into ANSI escape
*>      sequences in OUT-BUF and sent with one write(), so the
*>      screen does not flicker.
*>  The tty layout used (c_lflag, c_cc) is the Linux/glibc one.
*> ================================================================
IDENTIFICATION DIVISION.
PROGRAM-ID. INVADERS.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT HI-FILE ASSIGN TO "invaders.hi"
        ORGANIZATION IS LINE SEQUENTIAL
        FILE STATUS IS HI-STATUS.

DATA DIVISION.
FILE SECTION.
FD  HI-FILE.
01  HI-RECORD                   PIC 9(6).

WORKING-STORAGE SECTION.
*> ------------------------------------------------------ layout
78  SCR-ROWS                    VALUE 24.
78  SCR-COLS                    VALUE 80.
78  HUD-ROW                     VALUE 1.
78  UFO-ROW                     VALUE 2.
78  MSG-ROW                     VALUE 14.
78  SHIELD-TOP                  VALUE 17.
78  SHIELD-ROWS                 VALUE 3.
78  PLAYER-ROW                  VALUE 21.
78  GROUND-ROW                  VALUE 22.
78  HELP-ROW                    VALUE 24.
78  A-ROWS                      VALUE 5.
78  A-COLS                      VALUE 11.
78  A-XSTEP                     VALUE 6.
78  A-YSTEP                     VALUE 2.
78  MAX-BOMBS                   VALUE 6.
78  MAX-EXPL                    VALUE 4.
78  MAX-STARS                   VALUE 40.
78  PLAYER-MAX-X                VALUE 78.
78  UFO-MAX-X                   VALUE 76.
78  EXTRA-LIFE-SCORE            VALUE 1500.

*> ------------------------------------------------------ colours
*> Numbers from the xterm 256-colour palette.
78  CLR-WHITE                   VALUE 231.
78  CLR-LABEL                   VALUE 245.
78  CLR-HELP                    VALUE 242.
78  CLR-SHADOW                  VALUE 239.
78  CLR-YELLOW                  VALUE 226.
78  CLR-BOMB                    VALUE 214.
78  CLR-RED                     VALUE 196.
78  CLR-CYAN                    VALUE 51.
78  CLR-PLAYER                  VALUE 82.
78  CLR-GROUND                  VALUE 28.
78  CLR-TRAIL                   VALUE 39.

*> ------------------------------------------------------ terminal
01  TTY-SAVED                   PIC X(64).
01  TTY-RAW                     PIC X(64).
01  TTY-FLAG                    PIC X VALUE "N".
    88  TTY-OK                  VALUE "Y".
01  FD-IN                       PIC S9(18) COMP-5 VALUE 0.
01  FD-OUT                      PIC S9(18) COMP-5 VALUE 1.
01  TCSANOW                     PIC S9(18) COMP-5 VALUE 0.
01  IO-LEN                      PIC S9(18) COMP-5.
01  IO-RESULT                   PIC S9(9)  COMP-5.
01  LFLAG-BYTE                  PIC S9(4)  COMP-5.
01  LFLAG-HIGH                  PIC S9(4)  COMP-5.
01  LFLAG-LOW                   PIC S9(4)  COMP-5.
01  ESC-CHAR                    PIC X VALUE X"1B".
01  FULL-BLOCK                  PIC X(3) VALUE "█".
01  FRAME-NS                    PIC 9(10) COMP-5 VALUE 40000000.

01  IN-BUF                      PIC X(64).
01  IN-LEN                      PIC S9(9) COMP-5.
01  IN-POS                      PIC S9(4) COMP-5.
01  KEY-QUEUE.
    05  KEY-COUNT               PIC S9(4) COMP-5.
    05  KEY-EVENT               PIC X OCCURS 64 TIMES.
01  EV                          PIC X.
    88  EV-NONE                 VALUE SPACE.
    88  EV-LEFT                 VALUE "L".
    88  EV-RIGHT                VALUE "R".
    88  EV-FIRE                 VALUE "F".
    88  EV-PAUSE                VALUE "P".
    88  EV-QUIT                 VALUE "Q".
    88  EV-MUTE                 VALUE "M".

*> ------------------------------------------------------ screen
01  GRID.
    05  GRID-ROW                OCCURS SCR-ROWS TIMES.
        10  GRID-CELL           OCCURS SCR-COLS TIMES.
            15  CELL-CH         PIC X(4).
            15  CELL-LEN        PIC 9.
            15  CELL-CLR        PIC 999.
01  BLANK-GRID                  PIC X(15360).

01  OUT-BUF                     PIC X(40000).
01  OUT-PTR                     PIC S9(9) COMP-5.
01  CUR-CLR                     PIC S9(4) COMP-5.
01  ROW-NUM                     PIC 99.
01  CLR-NUM                     PIC 999.
01  FRAME-COUNT                 PIC S9(9) COMP-5 VALUE 0.

*> PUT-TEXT draws PT-TEXT (UTF-8) at PT-ROW/PT-COL in PT-CLR.
*> With PT-SHADOW set, everything but full blocks gets that colour;
*> with PT-SEE-THROUGH, spaces leave the cell below alone.
01  PT-TEXT                     PIC X(320).
01  PT-ROW                      PIC S9(4) COMP-5.
01  PT-COL                      PIC S9(4) COMP-5.
01  PT-CLR                      PIC S9(4) COMP-5.
01  PT-SHADOW                   PIC S9(4) COMP-5 VALUE 0.
01  PT-SEE-FLAG                 PIC X VALUE "N".
    88  PT-SEE-THROUGH          VALUE "Y".
    88  PT-SOLID                VALUE "N".
01  PT-BYTES                    PIC S9(4) COMP-5.
01  PT-I                        PIC S9(4) COMP-5.
01  PT-N                        PIC S9(4) COMP-5.
01  PT-B                        PIC S9(4) COMP-5.
01  PT-C                        PIC S9(4) COMP-5.

*> ------------------------------------------------------ sound
01  SND-NAME                    PIC X(10).
01  SND-CMD                     PIC X(200).
01  SND-PTR                     PIC S9(4) COMP-5.
01  SND-MARCH                   PIC 9 VALUE 1.
01  SND-TICK                    PIC S9(4) COMP-5 VALUE 0.
01  SOUND-FLAG                  PIC X VALUE "Y".
    88  SOUND-ON                VALUE "Y".
    88  SOUND-OFF               VALUE "N".

*> ------------------------------------------------------ sprites
01  SPRITE-DATA.
    05  FILLER                  PIC X(18) VALUE "▞█▚▚█▞".
    05  FILLER                  PIC X(18) VALUE "▜█▛▟█▙".
    05  FILLER                  PIC X(18) VALUE "▜█▛▟█▙".
    05  FILLER                  PIC X(18) VALUE "▄█▄▀█▀".
    05  FILLER                  PIC X(18) VALUE "▄█▄▀█▀".
01  SPRITE-TABLE REDEFINES SPRITE-DATA.
    05  SPRITE-ROW              OCCURS A-ROWS TIMES.
        10  SPRITE-FRAME        PIC X(9) OCCURS 2 TIMES.

01  ROW-COLOR-DATA              PIC X(15) VALUE "201141081120228".
01  ROW-COLOR-TABLE REDEFINES ROW-COLOR-DATA.
    05  ROW-COLOR               PIC 999 OCCURS A-ROWS TIMES.

01  UFO-SPRITE-DATA.
    05  FILLER                  PIC X(15) VALUE "▄▓█▓▄".
    05  FILLER                  PIC X(15) VALUE "▄█▓█▄".
01  UFO-SPRITE-TABLE REDEFINES UFO-SPRITE-DATA.
    05  UFO-SPRITE              PIC X(15) OCCURS 2 TIMES.

01  BURST-DATA.
    05  FILLER                  PIC X(9) VALUE "╲│╱".
    05  FILLER                  PIC X(9) VALUE "─┼─".
    05  FILLER                  PIC X(9) VALUE "╱│╲".
    05  FILLER                  PIC X(9) VALUE " · ".
01  BURST-TABLE REDEFINES BURST-DATA.
    05  BURST-FRAME             PIC X(9) OCCURS 4 TIMES.
01  BURST-COLOR-DATA            PIC X(12) VALUE "231226208196".
01  BURST-COLOR-TABLE REDEFINES BURST-COLOR-DATA.
    05  BURST-COLOR             PIC 999 OCCURS 4 TIMES.

01  SHADE-DATA                  PIC X(12) VALUE "░▒▓█".
01  SHADE-TABLE REDEFINES SHADE-DATA.
    05  SHADE-CHAR              PIC X(3) OCCURS 4 TIMES.
01  SHADE-COLOR-DATA            PIC X(12) VALUE "028034040046".
01  SHADE-COLOR-TABLE REDEFINES SHADE-COLOR-DATA.
    05  SHADE-COLOR             PIC 999 OCCURS 4 TIMES.

01  TITLE-ART-DATA.
    05  FILLER PIC X(200) VALUE
        "███████╗██████╗  ███"
      & "██╗  ██████╗███████╗".
    05  FILLER PIC X(200) VALUE
        "██╔════╝██╔══██╗██╔═"
      & "═██╗██╔════╝██╔════╝".
    05  FILLER PIC X(200) VALUE
        "███████╗██████╔╝████"
      & "███║██║     █████╗".
    05  FILLER PIC X(200) VALUE
        "╚════██║██╔═══╝ ██╔═"
      & "═██║██║     ██╔══╝".
    05  FILLER PIC X(200) VALUE
        "███████║██║     ██║ "
      & " ██║╚██████╗███████╗".
    05  FILLER PIC X(200) VALUE
        "╚══════╝╚═╝     ╚═╝ "
      & " ╚═╝ ╚═════╝╚══════╝".
    05  FILLER PIC X(200) VALUE
        "██╗███╗   ██╗██╗   █"
      & "█╗ █████╗ ██████╗ ██"
      & "█████╗██████╗ ██████"
      & "█╗".
    05  FILLER PIC X(200) VALUE
        "██║████╗  ██║██║   █"
      & "█║██╔══██╗██╔══██╗██"
      & "╔════╝██╔══██╗██╔═══"
      & "═╝".
    05  FILLER PIC X(200) VALUE
        "██║██╔██╗ ██║██║   █"
      & "█║███████║██║  ██║██"
      & "███╗  ██████╔╝██████"
      & "█╗".
    05  FILLER PIC X(200) VALUE
        "██║██║╚██╗██║╚██╗ ██"
      & "╔╝██╔══██║██║  ██║██"
      & "╔══╝  ██╔══██╗╚════█"
      & "█║".
    05  FILLER PIC X(200) VALUE
        "██║██║ ╚████║ ╚████╔"
      & "╝ ██║  ██║██████╔╝██"
      & "█████╗██║  ██║██████"
      & "█║".
    05  FILLER PIC X(200) VALUE
        "╚═╝╚═╝  ╚═══╝  ╚═══╝"
      & "  ╚═╝  ╚═╝╚═════╝ ╚═"
      & "═════╝╚═╝  ╚═╝╚═════"
      & "═╝".
01  TITLE-ART REDEFINES TITLE-ART-DATA.
    05  ART-LINE                PIC X(200) OCCURS 12 TIMES.
01  ART-COLOR-DATA              PIC X(36)
    VALUE "196202208214220226087081075069063057".
01  ART-COLOR-TABLE REDEFINES ART-COLOR-DATA.
    05  ART-COLOR               PIC 999 OCCURS 12 TIMES.

*> ------------------------------------------------------ game state
01  HI-STATUS                   PIC XX.
01  SCORE                       PIC 9(6).
01  HI-SCORE                    PIC 9(6) VALUE 0.
01  LIVES                       PIC 9.
01  WAVE                        PIC 99.
01  PROGRAM-FLAG                PIC X VALUE "N".
    88  QUIT-PROGRAM            VALUE "Y".
01  GAME-FLAG                   PIC X.
    88  GAME-RUNNING            VALUE "R".
    88  GAME-ENDED              VALUE "E".
01  START-FLAG                  PIC X.
    88  START-GAME              VALUE "Y".
01  PAUSE-FLAG                  PIC X.
    88  PAUSED                  VALUE "Y".
    88  NOT-PAUSED              VALUE "N".
01  BONUS-FLAG                  PIC X.
    88  BONUS-GIVEN             VALUE "Y".
01  HIT-FLAG                    PIC X.
    88  PLAYER-HIT              VALUE "Y".
    88  PLAYER-OK               VALUE "N".
01  OVER-FLAG                   PIC X VALUE "N".
    88  SHOW-GAME-OVER          VALUE "Y".
    88  HIDE-GAME-OVER          VALUE "N".
01  NEW-HI-FLAG                 PIC X.
    88  NEW-HI                  VALUE "Y".
01  MSG-TEXT                    PIC X(40).
01  MSG-LEN                     PIC S9(4) COMP-5 VALUE 0.

01  FORMATION.
    05  FORM-X                  PIC S9(4) COMP-5.
    05  FORM-Y                  PIC S9(4) COMP-5.
    05  FORM-DIR                PIC S9(4) COMP-5.
    05  MOVE-TIMER              PIC S9(4) COMP-5.
    05  MOVE-DELAY              PIC S9(4) COMP-5.
    05  ANIM-FRAME              PIC S9(4) COMP-5.
    05  ALIVE-COUNT             PIC S9(4) COMP-5.
    05  ALIEN-ROW               OCCURS A-ROWS TIMES.
        10  ALIEN-ALIVE         PIC 9 OCCURS A-COLS TIMES.

01  PLAYER-X                    PIC S9(4) COMP-5.
01  DEATH-TIMER                 PIC S9(4) COMP-5 VALUE 0.

01  BULLET.
    05  PB-FLAG                 PIC X.
        88  PB-ACTIVE           VALUE "Y".
        88  PB-IDLE             VALUE "N".
    05  PB-X                    PIC S9(4) COMP-5.
    05  PB-Y                    PIC S9(4) COMP-5.

01  BOMBS.
    05  BOMB-TIMER              PIC S9(4) COMP-5.
    05  BOMB-LIMIT              PIC S9(4) COMP-5.
    05  BOMB-DELAY              PIC S9(4) COMP-5.
    05  BOMB                    OCCURS MAX-BOMBS TIMES.
        10  BOMB-FLAG           PIC X.
            88  BOMB-ACTIVE     VALUE "Y".
            88  BOMB-IDLE       VALUE "N".
        10  BOMB-X              PIC S9(4) COMP-5.
        10  BOMB-Y              PIC S9(4) COMP-5.

01  UFO.
    05  UFO-FLAG                PIC X.
        88  UFO-ACTIVE          VALUE "Y".
        88  UFO-IDLE            VALUE "N".
    05  UFO-X                   PIC S9(4) COMP-5.
    05  UFO-DIR                 PIC S9(4) COMP-5.
    05  UFO-TIMER               PIC S9(4) COMP-5.
    05  UFO-POINTS              PIC 999.

*> Explosions: kind "A" is a burst where an invader died,
*> kind "U" shows the points the mystery ship was worth.
01  EXPLOSIONS.
    05  EXPL                    OCCURS MAX-EXPL TIMES.
        10  EXPL-TIMER          PIC S9(4) COMP-5.
        10  EXPL-KIND           PIC X.
        10  EXPL-X              PIC S9(4) COMP-5.
        10  EXPL-Y              PIC S9(4) COMP-5.
        10  EXPL-POINTS         PIC 999.
01  EXPL-NEW                    PIC S9(4) COMP-5.

*> Shield cells hold hit points: 4 = █, 3 = ▓, 2 = ▒, 1 = ░.
01  SHIELDS.
    05  SHIELD-ROW              OCCURS SHIELD-ROWS TIMES.
        10  SHIELD-HP           PIC 9 OCCURS SCR-COLS TIMES.
01  SHIELD-SHAPE-DATA.
    05  FILLER                  PIC X(7) VALUE " ##### ".
    05  FILLER                  PIC X(7) VALUE "#######".
    05  FILLER                  PIC X(7) VALUE "##   ##".
01  SHIELD-SHAPE REDEFINES SHIELD-SHAPE-DATA.
    05  SHAPE-LINE              PIC X(7) OCCURS SHIELD-ROWS TIMES.
01  SHIELD-POS-DATA             PIC X(8) VALUE "10284664".
01  SHIELD-POS-TABLE REDEFINES SHIELD-POS-DATA.
    05  SHIELD-POS              PIC 99 OCCURS 4 TIMES.
01  SH-ROW                      PIC S9(4) COMP-5.
01  SH-COL                      PIC S9(4) COMP-5.
01  SH-DMG                      PIC S9(4) COMP-5.

01  STARS.
    05  STAR                    OCCURS MAX-STARS TIMES.
        10  STAR-X              PIC S9(4) COMP-5.
        10  STAR-Y              PIC S9(4) COMP-5.
        10  STAR-PHASE          PIC S9(4) COMP-5.

*> ------------------------------------------------------ work fields
01  WORK-FIELDS.
    05  R                       PIC S9(4) COMP-5.
    05  C                       PIC S9(4) COMP-5.
    05  I                       PIC S9(4) COMP-5.
    05  J                       PIC S9(4) COMP-5.
    05  K                       PIC S9(4) COMP-5.
    05  AX                      PIC S9(4) COMP-5.
    05  AY                      PIC S9(4) COMP-5.
    05  MIN-C                   PIC S9(4) COMP-5.
    05  MAX-C                   PIC S9(4) COMP-5.
    05  MAX-R                   PIC S9(4) COMP-5.
    05  STAGE                   PIC S9(4) COMP-5.
    05  RND                     PIC S9(4) COMP-5.
    05  SEED                    PIC 9(8).
    05  DUMMY                   PIC 9V9(8).
    05  FOUND-FLAG              PIC X.
        88  FOUND               VALUE "Y".
        88  NOT-FOUND           VALUE "N".

PROCEDURE DIVISION.
MAIN-PARA.
    PERFORM INIT-PROGRAM
    PERFORM LOAD-HI-SCORE
    PERFORM UNTIL QUIT-PROGRAM
        PERFORM TITLE-SCREEN
        IF NOT QUIT-PROGRAM
            PERFORM PLAY-GAME
            PERFORM GAME-OVER-SCREEN
        END-IF
    END-PERFORM
    PERFORM SAVE-HI-SCORE
    PERFORM TTY-RESTORE
    STOP RUN.

*> ================================================================
*>  Setup and terminal handling
*> ================================================================
INIT-PROGRAM.
    MOVE FUNCTION CURRENT-DATE(9:8) TO SEED
    COMPUTE DUMMY = FUNCTION RANDOM(SEED)
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > SCR-ROWS
        PERFORM VARYING C FROM 1 BY 1 UNTIL C > SCR-COLS
            MOVE SPACE TO CELL-CH(R, C)
            MOVE 1 TO CELL-LEN(R, C)
            MOVE CLR-WHITE TO CELL-CLR(R, C)
        END-PERFORM
    END-PERFORM
    MOVE GRID TO BLANK-GRID
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-STARS
        COMPUTE STAR-X(I) = FUNCTION RANDOM * SCR-COLS + 1
        COMPUTE STAR-Y(I) = FUNCTION RANDOM * (PLAYER-ROW - 2) + 2
        COMPUTE STAR-PHASE(I) = FUNCTION RANDOM * 200
    END-PERFORM
    PERFORM TTY-RAW-MODE.

*>  Turn off ISIG (1), ICANON (2) and ECHO (8) in the low byte of
*>  c_lflag (bytes 13-16), and set VTIME (c_cc[5]) and VMIN
*>  (c_cc[6]) to 0 so read() returns at once.  Ctrl-C now arrives
*>  as a key, which quits cleanly instead of leaving a raw tty.
TTY-RAW-MODE.
    CALL "tcgetattr" USING BY VALUE FD-IN BY REFERENCE TTY-SAVED
        RETURNING IO-RESULT
    IF IO-RESULT = 0
        SET TTY-OK TO TRUE
        MOVE TTY-SAVED TO TTY-RAW
        COMPUTE LFLAG-BYTE = FUNCTION ORD(TTY-RAW(13:1)) - 1
        DIVIDE LFLAG-BYTE BY 16 GIVING LFLAG-HIGH REMAINDER LFLAG-LOW
        DIVIDE LFLAG-LOW BY 4 GIVING LFLAG-LOW
        COMPUTE LFLAG-BYTE = LFLAG-HIGH * 16
                           + FUNCTION MOD(LFLAG-LOW, 2) * 4
        MOVE FUNCTION CHAR(LFLAG-BYTE + 1) TO TTY-RAW(13:1)
        MOVE X"00" TO TTY-RAW(23:1)
        MOVE X"00" TO TTY-RAW(24:1)
        CALL "tcsetattr" USING BY VALUE FD-IN TCSANOW
            BY REFERENCE TTY-RAW
    END-IF
*>  Alternate screen, hide cursor, clear.
    MOVE 1 TO OUT-PTR
    STRING ESC-CHAR "[?1049h" ESC-CHAR "[?25l" ESC-CHAR "[2J"
        DELIMITED BY SIZE INTO OUT-BUF WITH POINTER OUT-PTR
    PERFORM WRITE-OUT.

TTY-RESTORE.
    MOVE 1 TO OUT-PTR
    STRING ESC-CHAR "[0m" ESC-CHAR "[2J" ESC-CHAR "[?25h"
           ESC-CHAR "[?1049l"
        DELIMITED BY SIZE INTO OUT-BUF WITH POINTER OUT-PTR
    PERFORM WRITE-OUT
    IF TTY-OK
        CALL "tcsetattr" USING BY VALUE FD-IN TCSANOW
            BY REFERENCE TTY-SAVED
    END-IF.

WRITE-OUT.
    COMPUTE IO-LEN = OUT-PTR - 1
    CALL "write" USING BY VALUE FD-OUT BY REFERENCE OUT-BUF
        BY VALUE IO-LEN RETURNING IO-RESULT.

FRAME-DELAY.
    CALL "CBL_GC_NANOSLEEP" USING FRAME-NS.

*>  Read whatever was typed since the last frame and turn it into
*>  events in KEY-QUEUE.  Arrow keys come as ESC [ C / ESC [ D.
POLL-KEYS.
    MOVE 0 TO KEY-COUNT
    MOVE 64 TO IO-LEN
    CALL "read" USING BY VALUE FD-IN BY REFERENCE IN-BUF
        BY VALUE IO-LEN RETURNING IN-LEN
    MOVE 1 TO IN-POS
    PERFORM UNTIL IN-POS > IN-LEN
        SET EV-NONE TO TRUE
        EVALUATE IN-BUF(IN-POS:1)
            WHEN ESC-CHAR
                IF IN-POS + 2 <= IN-LEN
                   AND (IN-BUF(IN-POS + 1:1) = "[" OR "O")
                    EVALUATE IN-BUF(IN-POS + 2:1)
                        WHEN "D" SET EV-LEFT TO TRUE
                        WHEN "C" SET EV-RIGHT TO TRUE
                    END-EVALUATE
                    ADD 2 TO IN-POS
                END-IF
            WHEN "a" WHEN "A" WHEN "h"
                SET EV-LEFT TO TRUE
            WHEN "d" WHEN "D" WHEN "l"
                SET EV-RIGHT TO TRUE
            WHEN " "
                SET EV-FIRE TO TRUE
            WHEN "p" WHEN "P"
                SET EV-PAUSE TO TRUE
            WHEN "m" WHEN "M"
                SET EV-MUTE TO TRUE
            WHEN "q" WHEN "Q" WHEN X"03"
                SET EV-QUIT TO TRUE
        END-EVALUATE
        IF NOT EV-NONE AND KEY-COUNT < 64
            ADD 1 TO KEY-COUNT
            MOVE EV TO KEY-EVENT(KEY-COUNT)
        END-IF
        ADD 1 TO IN-POS
    END-PERFORM.

LOAD-HI-SCORE.
    MOVE 0 TO HI-SCORE
    OPEN INPUT HI-FILE
    IF HI-STATUS = "00"
        READ HI-FILE
            NOT AT END
                IF HI-RECORD IS NUMERIC
                    MOVE HI-RECORD TO HI-SCORE
                END-IF
        END-READ
        CLOSE HI-FILE
    END-IF.

SAVE-HI-SCORE.
    OPEN OUTPUT HI-FILE
    IF HI-STATUS = "00"
        MOVE HI-SCORE TO HI-RECORD
        WRITE HI-RECORD
        CLOSE HI-FILE
    END-IF.

*> ================================================================
*>  Title and game-over screens
*> ================================================================
TITLE-SCREEN.
    MOVE "N" TO START-FLAG
    PERFORM UNTIL START-GAME OR QUIT-PROGRAM
        PERFORM POLL-KEYS
        PERFORM VARYING K FROM 1 BY 1 UNTIL K > KEY-COUNT
            MOVE KEY-EVENT(K) TO EV
            EVALUATE TRUE
                WHEN EV-FIRE SET START-GAME TO TRUE
                WHEN EV-QUIT SET QUIT-PROGRAM TO TRUE
                WHEN EV-MUTE PERFORM TOGGLE-SOUND
            END-EVALUATE
        END-PERFORM
        PERFORM RENDER-TITLE
        PERFORM FRAME-DELAY
    END-PERFORM.

RENDER-TITLE.
    MOVE BLANK-GRID TO GRID
    PERFORM DRAW-STARS
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > 12
        MOVE ART-LINE(I) TO PT-TEXT
        MOVE ART-COLOR(I) TO PT-CLR
        MOVE CLR-SHADOW TO PT-SHADOW
        SET PT-SEE-THROUGH TO TRUE
        IF I <= 6
            COMPUTE PT-ROW = I + 1
            MOVE 21 TO PT-COL
        ELSE
            COMPUTE PT-ROW = I + 2
            MOVE 10 TO PT-COL
        END-IF
        PERFORM PUT-TEXT
    END-PERFORM

    COMPUTE K = FUNCTION MOD(FRAME-COUNT / 12, 2) + 1
    MOVE UFO-SPRITE(K) TO PT-TEXT
    MOVE 16 TO PT-ROW  MOVE 30 TO PT-COL  MOVE CLR-RED TO PT-CLR
    PERFORM PUT-TEXT
    MOVE SPRITE-FRAME(1, K) TO PT-TEXT
    MOVE 17 TO PT-ROW  MOVE 31 TO PT-COL  MOVE ROW-COLOR(1) TO PT-CLR
    PERFORM PUT-TEXT
    MOVE SPRITE-FRAME(2, K) TO PT-TEXT
    MOVE 18 TO PT-ROW  MOVE ROW-COLOR(2) TO PT-CLR
    PERFORM PUT-TEXT
    MOVE SPRITE-FRAME(4, K) TO PT-TEXT
    MOVE 19 TO PT-ROW  MOVE ROW-COLOR(4) TO PT-CLR
    PERFORM PUT-TEXT
    MOVE CLR-LABEL TO PT-CLR
    MOVE 37 TO PT-COL
    MOVE "=  ? MYSTERY" TO PT-TEXT  MOVE 16 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "=  30 POINTS" TO PT-TEXT  MOVE 17 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "=  20 POINTS" TO PT-TEXT  MOVE 18 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "=  10 POINTS" TO PT-TEXT  MOVE 19 TO PT-ROW  PERFORM PUT-TEXT

    MOVE SPACES TO PT-TEXT
    STRING "HI-SCORE  " HI-SCORE DELIMITED BY SIZE INTO PT-TEXT
    MOVE 21 TO PT-ROW  MOVE 33 TO PT-COL  MOVE CLR-YELLOW TO PT-CLR
    PERFORM PUT-TEXT
    IF FUNCTION MOD(FRAME-COUNT, 24) < 16
        MOVE "▶ PRESS SPACE TO PLAY ◀" TO PT-TEXT
        MOVE 22 TO PT-ROW  MOVE 29 TO PT-COL  MOVE CLR-WHITE TO PT-CLR
        PERFORM PUT-TEXT
    END-IF
    PERFORM DRAW-HELP
    PERFORM EMIT-FRAME.

GAME-OVER-SCREEN.
    IF NEW-HI
        PERFORM SAVE-HI-SCORE
    END-IF
    SET SHOW-GAME-OVER TO TRUE
    MOVE "gameover" TO SND-NAME
    PERFORM PLAY-SOUND
*>  Ignore keys for a second so a held fire key does not skip this.
    PERFORM 25 TIMES
        PERFORM POLL-KEYS
        PERFORM RENDER-GAME
        PERFORM FRAME-DELAY
    END-PERFORM
    MOVE "N" TO START-FLAG
    PERFORM UNTIL START-GAME
        PERFORM POLL-KEYS
        PERFORM VARYING K FROM 1 BY 1 UNTIL K > KEY-COUNT
            MOVE KEY-EVENT(K) TO EV
            EVALUATE TRUE
                WHEN EV-FIRE
                    SET START-GAME TO TRUE
                WHEN EV-QUIT
                    SET START-GAME TO TRUE
                    SET QUIT-PROGRAM TO TRUE
            END-EVALUATE
        END-PERFORM
        PERFORM RENDER-GAME
        PERFORM FRAME-DELAY
    END-PERFORM
    SET HIDE-GAME-OVER TO TRUE.

*> ================================================================
*>  Main game loop
*> ================================================================
PLAY-GAME.
    MOVE 0 TO SCORE
    MOVE 3 TO LIVES
    MOVE 1 TO WAVE
    MOVE "N" TO BONUS-FLAG
    MOVE "N" TO NEW-HI-FLAG
    SET NOT-PAUSED TO TRUE
    SET GAME-RUNNING TO TRUE
    PERFORM START-WAVE
    PERFORM UNTIL GAME-ENDED
        PERFORM READ-INPUT
        IF GAME-RUNNING AND NOT-PAUSED
            PERFORM UPDATE-BULLET
            PERFORM UPDATE-BULLET
            PERFORM UPDATE-ALIENS
            PERFORM UPDATE-UFO
            PERFORM DROP-BOMB
            PERFORM UPDATE-BOMBS
            PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-EXPL
                IF EXPL-TIMER(I) > 0
                    SUBTRACT 1 FROM EXPL-TIMER(I)
                END-IF
            END-PERFORM
            IF GAME-RUNNING AND ALIVE-COUNT = 0
                ADD 1 TO WAVE
                PERFORM START-WAVE
            END-IF
        END-IF
        PERFORM RENDER-GAME
        PERFORM FRAME-DELAY
    END-PERFORM.

START-WAVE.
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > A-ROWS
        PERFORM VARYING C FROM 1 BY 1 UNTIL C > A-COLS
            MOVE 1 TO ALIEN-ALIVE(R, C)
        END-PERFORM
    END-PERFORM
    COMPUTE ALIVE-COUNT = A-ROWS * A-COLS
    MOVE 9 TO FORM-X
    COMPUTE FORM-Y = 4 + FUNCTION MIN(WAVE - 1, 4)
    MOVE 1 TO FORM-DIR
    MOVE 0 TO MOVE-TIMER
    MOVE 1 TO ANIM-FRAME
    PERFORM SET-MOVE-DELAY
    PERFORM RESET-SHIELDS
    MOVE 39 TO PLAYER-X
    PERFORM CLEAR-SHOTS
    SET UFO-IDLE TO TRUE
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-EXPL
        MOVE 0 TO EXPL-TIMER(I)
    END-PERFORM
    IF WAVE < 3
        MOVE 3 TO BOMB-DELAY
    ELSE
        MOVE 2 TO BOMB-DELAY
    END-IF
    COMPUTE BOMB-LIMIT = FUNCTION MIN(1 + WAVE, MAX-BOMBS)
    MOVE SPACES TO MSG-TEXT
    STRING "W A V E   " WAVE DELIMITED BY SIZE INTO MSG-TEXT
    MOVE 12 TO MSG-LEN
    MOVE "wave" TO SND-NAME
    PERFORM PLAY-SOUND
    PERFORM 40 TIMES
        PERFORM POLL-KEYS
        PERFORM RENDER-GAME
        PERFORM FRAME-DELAY
    END-PERFORM
    MOVE 0 TO MSG-LEN.

RESET-SHIELDS.
    MOVE ZEROS TO SHIELDS
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > 4
        PERFORM VARYING J FROM 1 BY 1 UNTIL J > SHIELD-ROWS
            PERFORM VARYING K FROM 1 BY 1 UNTIL K > 7
                IF SHAPE-LINE(J)(K:1) = "#"
                    COMPUTE C = SHIELD-POS(I) + K - 1
                    MOVE 4 TO SHIELD-HP(J, C)
                END-IF
            END-PERFORM
        END-PERFORM
    END-PERFORM.

*>  Knock SH-DMG hit points off the shield cell at SH-ROW/SH-COL
*>  (a screen position; anything outside the shields is ignored).
DAMAGE-SHIELD.
    IF SH-ROW >= SHIELD-TOP AND SH-ROW < SHIELD-TOP + SHIELD-ROWS
       AND SH-COL >= 1 AND SH-COL <= SCR-COLS
        COMPUTE J = SH-ROW - SHIELD-TOP + 1
        IF SHIELD-HP(J, SH-COL) > SH-DMG
            SUBTRACT SH-DMG FROM SHIELD-HP(J, SH-COL)
        ELSE
            MOVE 0 TO SHIELD-HP(J, SH-COL)
        END-IF
    END-IF.

CLEAR-SHOTS.
    SET PB-IDLE TO TRUE
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
        SET BOMB-IDLE(I) TO TRUE
    END-PERFORM
    MOVE 0 TO BOMB-TIMER.

*>  Fewer invaders left (or a later wave) means faster marching.
SET-MOVE-DELAY.
*>  Wave 1 goes from 17 frames per step with a full formation down
*>  to 6 with the last invader; later waves are a frame faster each,
*>  but never faster than one step per 3 frames.
    COMPUTE MOVE-DELAY = 6 + ALIVE-COUNT / 5 - (WAVE - 1)
    IF MOVE-DELAY < 3
        MOVE 3 TO MOVE-DELAY
    END-IF.

READ-INPUT.
    PERFORM POLL-KEYS
    PERFORM VARYING K FROM 1 BY 1 UNTIL K > KEY-COUNT
        MOVE KEY-EVENT(K) TO EV
        EVALUATE TRUE
            WHEN EV-QUIT
                SET GAME-ENDED TO TRUE
            WHEN EV-MUTE
                PERFORM TOGGLE-SOUND
            WHEN EV-PAUSE
                IF PAUSED
                    SET NOT-PAUSED TO TRUE
                ELSE
                    SET PAUSED TO TRUE
                END-IF
            WHEN PAUSED
                CONTINUE
            WHEN EV-LEFT
                SUBTRACT 2 FROM PLAYER-X
                IF PLAYER-X < 1
                    MOVE 1 TO PLAYER-X
                END-IF
            WHEN EV-RIGHT
                ADD 2 TO PLAYER-X
                IF PLAYER-X > PLAYER-MAX-X
                    MOVE PLAYER-MAX-X TO PLAYER-X
                END-IF
            WHEN EV-FIRE
                IF PB-IDLE
                    SET PB-ACTIVE TO TRUE
                    COMPUTE PB-X = PLAYER-X + 1
                    MOVE PLAYER-ROW TO PB-Y
                    MOVE "shoot" TO SND-NAME
                    PERFORM PLAY-SOUND
                END-IF
        END-EVALUATE
    END-PERFORM.

*> ================================================================
*>  Player's laser
*> ================================================================
UPDATE-BULLET.
    IF PB-ACTIVE
        SUBTRACT 1 FROM PB-Y
        IF PB-Y < UFO-ROW
            SET PB-IDLE TO TRUE
        ELSE
            PERFORM BULLET-HITS-SHIELD
            PERFORM BULLET-HITS-BOMB
            PERFORM BULLET-HITS-ALIEN
            PERFORM BULLET-HITS-UFO
        END-IF
    END-IF.

BULLET-HITS-SHIELD.
    IF PB-Y >= SHIELD-TOP AND PB-Y < SHIELD-TOP + SHIELD-ROWS
        COMPUTE I = PB-Y - SHIELD-TOP + 1
        IF SHIELD-HP(I, PB-X) > 0
            MOVE PB-Y TO SH-ROW
            MOVE PB-X TO SH-COL
            MOVE 2 TO SH-DMG
            PERFORM DAMAGE-SHIELD
            SET PB-IDLE TO TRUE
            MOVE "hit" TO SND-NAME
            PERFORM PLAY-SOUND
        END-IF
    END-IF.

BULLET-HITS-BOMB.
    IF PB-ACTIVE
        PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
            IF BOMB-ACTIVE(I) AND BOMB-X(I) = PB-X
                              AND BOMB-Y(I) = PB-Y
                SET BOMB-IDLE(I) TO TRUE
                SET PB-IDLE TO TRUE
                MOVE PB-X TO AX
                MOVE PB-Y TO AY
                MOVE 10 TO K
                PERFORM ADD-BURST
            END-IF
        END-PERFORM
    END-IF.

*>  The grid position follows from the formation's origin, so the
*>  invader (if any) under the laser is found without a search.
BULLET-HITS-ALIEN.
    IF PB-ACTIVE
        COMPUTE I = PB-Y - FORM-Y
        COMPUTE J = PB-X - FORM-X
        IF I >= 0 AND J >= 0
            DIVIDE I BY A-YSTEP GIVING R REMAINDER K
            ADD 1 TO R
            IF K = 0 AND R <= A-ROWS
                DIVIDE J BY A-XSTEP GIVING C REMAINDER K
                ADD 1 TO C
                IF K <= 2 AND C <= A-COLS
                    IF ALIEN-ALIVE(R, C) = 1
                        PERFORM KILL-ALIEN
                    END-IF
                END-IF
            END-IF
        END-IF
    END-IF.

KILL-ALIEN.
    MOVE 0 TO ALIEN-ALIVE(R, C)
    SUBTRACT 1 FROM ALIVE-COUNT
    SET PB-IDLE TO TRUE
    EVALUATE R
        WHEN 1        MOVE 30 TO K
        WHEN 2 THRU 3 MOVE 20 TO K
        WHEN OTHER    MOVE 10 TO K
    END-EVALUATE
    PERFORM ADD-SCORE
    MOVE "kill" TO SND-NAME
    PERFORM PLAY-SOUND
    COMPUTE AX = FORM-X + (C - 1) * A-XSTEP
    COMPUTE AY = FORM-Y + (R - 1) * A-YSTEP
    PERFORM ADD-BURST
    PERFORM SET-MOVE-DELAY.

*>  Start a burst at AX/AY (left edge of a 3-wide sprite) in the
*>  slot that is closest to finishing.
ADD-BURST.
    PERFORM FIND-EXPL-SLOT
    MOVE "A" TO EXPL-KIND(EXPL-NEW)
    MOVE 8 TO EXPL-TIMER(EXPL-NEW)
    MOVE AX TO EXPL-X(EXPL-NEW)
    MOVE AY TO EXPL-Y(EXPL-NEW).

FIND-EXPL-SLOT.
    MOVE 1 TO EXPL-NEW
    PERFORM VARYING I FROM 2 BY 1 UNTIL I > MAX-EXPL
        IF EXPL-TIMER(I) < EXPL-TIMER(EXPL-NEW)
            MOVE I TO EXPL-NEW
        END-IF
    END-PERFORM.

BULLET-HITS-UFO.
    IF PB-ACTIVE AND UFO-ACTIVE AND PB-Y = UFO-ROW
       AND PB-X >= UFO-X AND PB-X <= UFO-X + 4
        SET PB-IDLE TO TRUE
        SET UFO-IDLE TO TRUE
        MOVE UFO-POINTS TO K
        PERFORM ADD-SCORE
        MOVE "ufohit" TO SND-NAME
        PERFORM PLAY-SOUND
        PERFORM FIND-EXPL-SLOT
        MOVE "U" TO EXPL-KIND(EXPL-NEW)
        MOVE 40 TO EXPL-TIMER(EXPL-NEW)
        MOVE UFO-X TO EXPL-X(EXPL-NEW)
        MOVE UFO-ROW TO EXPL-Y(EXPL-NEW)
        MOVE UFO-POINTS TO EXPL-POINTS(EXPL-NEW)
    END-IF.

ADD-SCORE.
    ADD K TO SCORE
    IF SCORE > HI-SCORE
        MOVE SCORE TO HI-SCORE
        SET NEW-HI TO TRUE
    END-IF
    IF SCORE >= EXTRA-LIFE-SCORE AND NOT BONUS-GIVEN
        SET BONUS-GIVEN TO TRUE
        IF LIVES < 9
            ADD 1 TO LIVES
        END-IF
    END-IF.

*> ================================================================
*>  Invaders
*> ================================================================
UPDATE-ALIENS.
    ADD 1 TO MOVE-TIMER
    IF MOVE-TIMER >= MOVE-DELAY AND ALIVE-COUNT > 0
        MOVE 0 TO MOVE-TIMER
        PERFORM FIND-EXTENTS
        IF (FORM-DIR > 0 AND
            FORM-X + (MAX-C - 1) * A-XSTEP + 3 > SCR-COLS)
        OR (FORM-DIR < 0 AND
            FORM-X + (MIN-C - 1) * A-XSTEP - 1 < 1)
            ADD 1 TO FORM-Y
            COMPUTE FORM-DIR = 0 - FORM-DIR
        ELSE
            ADD FORM-DIR TO FORM-X
        END-IF
        COMPUTE ANIM-FRAME = 3 - ANIM-FRAME
        PERFORM PLAY-MARCH
        PERFORM ALIENS-CRUSH-SHIELDS
        IF FORM-Y + (MAX-R - 1) * A-YSTEP >= PLAYER-ROW
*>          They have landed: the game is lost outright.
            MOVE 0 TO LIVES
            PERFORM PLAYER-DIES
        END-IF
    END-IF.

FIND-EXTENTS.
    MOVE 99 TO MIN-C
    MOVE 0 TO MAX-C MAX-R
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > A-ROWS
        PERFORM VARYING C FROM 1 BY 1 UNTIL C > A-COLS
            IF ALIEN-ALIVE(R, C) = 1
                IF C < MIN-C
                    MOVE C TO MIN-C
                END-IF
                IF C > MAX-C
                    MOVE C TO MAX-C
                END-IF
                MOVE R TO MAX-R
            END-IF
        END-PERFORM
    END-PERFORM.

ALIENS-CRUSH-SHIELDS.
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > A-ROWS
        COMPUTE AY = FORM-Y + (R - 1) * A-YSTEP
        IF AY >= SHIELD-TOP AND AY < SHIELD-TOP + SHIELD-ROWS
            COMPUTE I = AY - SHIELD-TOP + 1
            PERFORM VARYING C FROM 1 BY 1 UNTIL C > A-COLS
                IF ALIEN-ALIVE(R, C) = 1
                    COMPUTE AX = FORM-X + (C - 1) * A-XSTEP
                    MOVE 0 TO SHIELD-HP(I, AX)
                    MOVE 0 TO SHIELD-HP(I, AX + 1)
                    MOVE 0 TO SHIELD-HP(I, AX + 2)
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM.

*>  Now and then the lowest invader in some column drops a bomb;
*>  half of the time it is the column right above the player.
DROP-BOMB.
    MOVE 0 TO K
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
        IF BOMB-ACTIVE(I)
            ADD 1 TO K
        END-IF
    END-PERFORM
    COMPUTE RND = FUNCTION RANDOM * 1000
    IF K < BOMB-LIMIT AND RND < 12 + WAVE * 8 AND ALIVE-COUNT > 0
        IF FUNCTION RANDOM < 0.3
            COMPUTE C = (PLAYER-X + 1 - FORM-X) / A-XSTEP + 1
        ELSE
            COMPUTE C = FUNCTION RANDOM * A-COLS + 1
        END-IF
        IF C < 1 OR C > A-COLS
            COMPUTE C = FUNCTION RANDOM * A-COLS + 1
        END-IF
*>      Walk to the right (wrapping) until a column with invaders.
        SET NOT-FOUND TO TRUE
        PERFORM A-COLS TIMES
            PERFORM VARYING R FROM A-ROWS BY -1 UNTIL R < 1 OR FOUND
                IF ALIEN-ALIVE(R, C) = 1
                    SET FOUND TO TRUE
                END-IF
            END-PERFORM
            IF FOUND
                EXIT PERFORM
            END-IF
            ADD 1 TO C
            IF C > A-COLS
                MOVE 1 TO C
            END-IF
        END-PERFORM
        IF FOUND
*>          The VARYING loop stepped once past the invader it found.
            ADD 1 TO R
            PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
                IF BOMB-IDLE(I)
                    SET BOMB-ACTIVE(I) TO TRUE
                    COMPUTE BOMB-X(I) = FORM-X + (C - 1) * A-XSTEP + 1
                    COMPUTE BOMB-Y(I) = FORM-Y + (R - 1) * A-YSTEP
                    EXIT PERFORM
                END-IF
            END-PERFORM
        END-IF
    END-IF.

UPDATE-BOMBS.
    SET PLAYER-OK TO TRUE
    ADD 1 TO BOMB-TIMER
    IF BOMB-TIMER >= BOMB-DELAY
        MOVE 0 TO BOMB-TIMER
        PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
            IF BOMB-ACTIVE(I)
                ADD 1 TO BOMB-Y(I)
                PERFORM BOMB-COLLISIONS
            END-IF
        END-PERFORM
    END-IF
    IF PLAYER-HIT
        SUBTRACT 1 FROM LIVES
        PERFORM PLAYER-DIES
    END-IF.

*>  A bomb blows a hole in a shield: two hit points where it lands,
*>  one on either side.
BOMB-COLLISIONS.
    EVALUATE TRUE
        WHEN BOMB-Y(I) >= GROUND-ROW
            SET BOMB-IDLE(I) TO TRUE
        WHEN BOMB-Y(I) >= SHIELD-TOP
         AND BOMB-Y(I) < SHIELD-TOP + SHIELD-ROWS
            COMPUTE J = BOMB-Y(I) - SHIELD-TOP + 1
            IF SHIELD-HP(J, BOMB-X(I)) > 0
                MOVE BOMB-Y(I) TO SH-ROW
                MOVE BOMB-X(I) TO SH-COL
                MOVE 2 TO SH-DMG
                PERFORM DAMAGE-SHIELD
                MOVE 1 TO SH-DMG
                SUBTRACT 1 FROM SH-COL
                PERFORM DAMAGE-SHIELD
                ADD 2 TO SH-COL
                PERFORM DAMAGE-SHIELD
                SET BOMB-IDLE(I) TO TRUE
                MOVE "hit" TO SND-NAME
                PERFORM PLAY-SOUND
            END-IF
        WHEN BOMB-Y(I) = PLAYER-ROW
         AND BOMB-X(I) >= PLAYER-X AND BOMB-X(I) <= PLAYER-X + 2
            SET BOMB-IDLE(I) TO TRUE
            SET PLAYER-HIT TO TRUE
    END-EVALUATE
    IF BOMB-ACTIVE(I) AND PB-ACTIVE
       AND BOMB-X(I) = PB-X AND BOMB-Y(I) = PB-Y
        SET BOMB-IDLE(I) TO TRUE
        SET PB-IDLE TO TRUE
    END-IF.

*>  Freeze the world and let the ship burn for a little while.
PLAYER-DIES.
    PERFORM CLEAR-SHOTS
    MOVE "dead" TO SND-NAME
    PERFORM PLAY-SOUND
    PERFORM VARYING DEATH-TIMER FROM 40 BY -1 UNTIL DEATH-TIMER = 0
        PERFORM POLL-KEYS
        PERFORM RENDER-GAME
        PERFORM FRAME-DELAY
    END-PERFORM
    IF LIVES = 0
        SET GAME-ENDED TO TRUE
    ELSE
        MOVE 39 TO PLAYER-X
    END-IF.

*> ================================================================
*>  Mystery ship
*> ================================================================
UPDATE-UFO.
    IF UFO-ACTIVE
        ADD 1 TO SND-TICK
        IF SND-TICK >= 8
            MOVE 0 TO SND-TICK
            MOVE "ufo" TO SND-NAME
            PERFORM PLAY-SOUND
        END-IF
        ADD 1 TO UFO-TIMER
        IF UFO-TIMER >= 2
            MOVE 0 TO UFO-TIMER
            ADD UFO-DIR TO UFO-X
            IF UFO-X < 1 OR UFO-X > UFO-MAX-X
                SET UFO-IDLE TO TRUE
            END-IF
        END-IF
    ELSE
        IF ALIVE-COUNT > 7 AND FUNCTION RANDOM < 0.002
            SET UFO-ACTIVE TO TRUE
            MOVE 0 TO UFO-TIMER
            IF FUNCTION RANDOM < 0.5
                MOVE 1 TO UFO-X
                MOVE 1 TO UFO-DIR
            ELSE
                MOVE UFO-MAX-X TO UFO-X
                MOVE -1 TO UFO-DIR
            END-IF
            COMPUTE UFO-POINTS = (FUNCTION INTEGER(FUNCTION RANDOM * 6)
                                  + 1) * 50
        END-IF
    END-IF.

*> ================================================================
*>  Sound
*> ================================================================
*>  Fire and forget: the shell starts the player in the background
*>  and returns at once, so the game never waits for a sound.
PLAY-SOUND.
    IF SOUND-ON
        MOVE 1 TO SND-PTR
        MOVE SPACES TO SND-CMD
        STRING "f=sounds/" FUNCTION TRIM(SND-NAME) ".wav; "
               "[ -f $f ] && { pw-play $f || paplay $f || aplay -q $f; }"
               " >/dev/null 2>&1 &" X"00"
            DELIMITED BY SIZE INTO SND-CMD WITH POINTER SND-PTR
        CALL "SYSTEM" USING SND-CMD
    END-IF.

*>  The classic four-note heartbeat, once per step of the
*>  formation.  Late in a wave, when the steps come every frame,
*>  only every other one sounds.
PLAY-MARCH.
    ADD 1 TO SND-MARCH
    IF SND-MARCH > 4
        MOVE 1 TO SND-MARCH
    END-IF
    IF MOVE-DELAY > 1 OR FUNCTION MOD(SND-MARCH, 2) = 0
        MOVE SPACES TO SND-NAME
        STRING "march" SND-MARCH DELIMITED BY SIZE INTO SND-NAME
        PERFORM PLAY-SOUND
    END-IF.

TOGGLE-SOUND.
    IF SOUND-ON
        SET SOUND-OFF TO TRUE
    ELSE
        SET SOUND-ON TO TRUE
    END-IF.

*> ================================================================
*>  Drawing
*> ================================================================
RENDER-GAME.
    MOVE BLANK-GRID TO GRID
    PERFORM DRAW-STARS
    PERFORM DRAW-HUD
    PERFORM DRAW-SHIELDS
    PERFORM DRAW-ALIENS
    PERFORM DRAW-UFO
    PERFORM DRAW-EXPLOSIONS
    PERFORM DRAW-SHOTS
    PERFORM DRAW-PLAYER
    PERFORM VARYING C FROM 1 BY 1 UNTIL C > SCR-COLS
        MOVE "▀" TO CELL-CH(GROUND-ROW, C)
        MOVE 3 TO CELL-LEN(GROUND-ROW, C)
        MOVE CLR-GROUND TO CELL-CLR(GROUND-ROW, C)
    END-PERFORM
    PERFORM DRAW-HELP
    IF PAUSED
        MOVE "‖  P A U S E D  ‖" TO PT-TEXT
        MOVE MSG-ROW TO PT-ROW  MOVE 33 TO PT-COL
        MOVE CLR-YELLOW TO PT-CLR
        PERFORM PUT-TEXT
    END-IF
    IF MSG-LEN > 0
        MOVE MSG-TEXT TO PT-TEXT
        MOVE MSG-ROW TO PT-ROW
        COMPUTE PT-COL = 41 - MSG-LEN / 2
        MOVE CLR-YELLOW TO PT-CLR
        PERFORM PUT-TEXT
    END-IF
    IF SHOW-GAME-OVER
        PERFORM DRAW-GAME-OVER
    END-IF
    PERFORM EMIT-FRAME.

*>  Stars twinkle: each spends a few frames of its cycle bright.
DRAW-STARS.
    SET PT-SOLID TO TRUE
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-STARS
        COMPUTE K = FUNCTION MOD(FRAME-COUNT + STAR-PHASE(I), 90)
        EVALUATE TRUE
            WHEN K < 3
                MOVE "✦" TO PT-TEXT  MOVE 255 TO PT-CLR
            WHEN K < 6
                MOVE "+" TO PT-TEXT  MOVE 250 TO PT-CLR
            WHEN FUNCTION MOD(I, 3) = 0
                MOVE "." TO PT-TEXT  MOVE 240 TO PT-CLR
            WHEN OTHER
                MOVE "·" TO PT-TEXT  MOVE 237 TO PT-CLR
        END-EVALUATE
        MOVE STAR-Y(I) TO PT-ROW
        MOVE STAR-X(I) TO PT-COL
        PERFORM PUT-TEXT
    END-PERFORM.

DRAW-HUD.
    MOVE HUD-ROW TO PT-ROW
    MOVE CLR-LABEL TO PT-CLR
    MOVE "SCORE"    TO PT-TEXT  MOVE 2  TO PT-COL  PERFORM PUT-TEXT
    MOVE "HI-SCORE" TO PT-TEXT  MOVE 22 TO PT-COL  PERFORM PUT-TEXT
    MOVE "WAVE"     TO PT-TEXT  MOVE 45 TO PT-COL  PERFORM PUT-TEXT
    MOVE "LIVES"    TO PT-TEXT  MOVE 58 TO PT-COL  PERFORM PUT-TEXT
    MOVE SCORE    TO PT-TEXT  MOVE 8  TO PT-COL
    MOVE CLR-WHITE TO PT-CLR   PERFORM PUT-TEXT
    MOVE HI-SCORE TO PT-TEXT  MOVE 31 TO PT-COL
    MOVE CLR-YELLOW TO PT-CLR  PERFORM PUT-TEXT
    MOVE WAVE     TO PT-TEXT  MOVE 50 TO PT-COL
    MOVE CLR-CYAN TO PT-CLR    PERFORM PUT-TEXT
    MOVE CLR-PLAYER TO PT-CLR
    MOVE "▲" TO PT-TEXT
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > LIVES
        COMPUTE PT-COL = 64 + (I - 1) * 2
        PERFORM PUT-TEXT
    END-PERFORM.

DRAW-HELP.
    MOVE "←/→ or A/D move   SPACE fire   P pause   M sound   Q quit"
      TO PT-TEXT
    MOVE HELP-ROW TO PT-ROW  MOVE 11 TO PT-COL  MOVE CLR-HELP TO PT-CLR
    PERFORM PUT-TEXT
    IF SOUND-OFF
        MOVE "♪ OFF" TO PT-TEXT
        MOVE HUD-ROW TO PT-ROW  MOVE 75 TO PT-COL
        MOVE CLR-HELP TO PT-CLR
        PERFORM PUT-TEXT
    END-IF.

DRAW-SHIELDS.
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > SHIELD-ROWS
        COMPUTE R = SHIELD-TOP + I - 1
        PERFORM VARYING C FROM 1 BY 1 UNTIL C > SCR-COLS
            IF SHIELD-HP(I, C) > 0
                MOVE SHADE-CHAR(SHIELD-HP(I, C)) TO CELL-CH(R, C)
                MOVE 3 TO CELL-LEN(R, C)
                MOVE SHADE-COLOR(SHIELD-HP(I, C)) TO CELL-CLR(R, C)
            END-IF
        END-PERFORM
    END-PERFORM.

DRAW-ALIENS.
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > A-ROWS
        COMPUTE AY = FORM-Y + (R - 1) * A-YSTEP
        IF AY < GROUND-ROW
            PERFORM VARYING C FROM 1 BY 1 UNTIL C > A-COLS
                IF ALIEN-ALIVE(R, C) = 1
                    MOVE SPRITE-FRAME(R, ANIM-FRAME) TO PT-TEXT
                    MOVE AY TO PT-ROW
                    COMPUTE PT-COL = FORM-X + (C - 1) * A-XSTEP
                    MOVE ROW-COLOR(R) TO PT-CLR
                    PERFORM PUT-TEXT
                END-IF
            END-PERFORM
        END-IF
    END-PERFORM.

DRAW-UFO.
    IF UFO-ACTIVE
        COMPUTE K = FUNCTION MOD(FRAME-COUNT / 4, 2) + 1
        MOVE UFO-SPRITE(K) TO PT-TEXT
        MOVE UFO-ROW TO PT-ROW  MOVE UFO-X TO PT-COL
        MOVE CLR-RED TO PT-CLR
        PERFORM PUT-TEXT
    END-IF.

DRAW-EXPLOSIONS.
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-EXPL
        IF EXPL-TIMER(I) > 0
            MOVE EXPL-Y(I) TO PT-ROW
            MOVE EXPL-X(I) TO PT-COL
            IF EXPL-KIND(I) = "U"
                MOVE SPACES TO PT-TEXT
                STRING "+" EXPL-POINTS(I) DELIMITED BY SIZE INTO PT-TEXT
                IF FUNCTION MOD(EXPL-TIMER(I) / 3, 2) = 0
                    MOVE CLR-YELLOW TO PT-CLR
                ELSE
                    MOVE CLR-WHITE TO PT-CLR
                END-IF
            ELSE
                COMPUTE STAGE = (8 - EXPL-TIMER(I)) / 2 + 1
                MOVE BURST-FRAME(STAGE) TO PT-TEXT
                MOVE BURST-COLOR(STAGE) TO PT-CLR
            END-IF
            PERFORM PUT-TEXT
        END-IF
    END-PERFORM.

*>  Bombs zig-zag as they fall; the laser leaves a short trail.
DRAW-SHOTS.
    MOVE CLR-BOMB TO PT-CLR
    PERFORM VARYING I FROM 1 BY 1 UNTIL I > MAX-BOMBS
        IF BOMB-ACTIVE(I)
            IF FUNCTION MOD(BOMB-Y(I), 2) = 0
                MOVE "╱" TO PT-TEXT
            ELSE
                MOVE "╲" TO PT-TEXT
            END-IF
            MOVE BOMB-Y(I) TO PT-ROW
            MOVE BOMB-X(I) TO PT-COL
            PERFORM PUT-TEXT
        END-IF
    END-PERFORM
    IF PB-ACTIVE
        MOVE PB-X TO PT-COL
        IF PB-Y + 1 < PLAYER-ROW
            MOVE "╵" TO PT-TEXT
            COMPUTE PT-ROW = PB-Y + 1
            MOVE CLR-TRAIL TO PT-CLR
            PERFORM PUT-TEXT
        END-IF
        MOVE "┃" TO PT-TEXT
        MOVE PB-Y TO PT-ROW
        MOVE CLR-WHITE TO PT-CLR
        PERFORM PUT-TEXT
    END-IF.

DRAW-PLAYER.
    MOVE PLAYER-ROW TO PT-ROW
    MOVE PLAYER-X TO PT-COL
    EVALUATE TRUE
        WHEN DEATH-TIMER = 0
            MOVE "▄▲▄" TO PT-TEXT
            MOVE CLR-PLAYER TO PT-CLR
        WHEN DEATH-TIMER <= 10
            MOVE "░▒░" TO PT-TEXT
            MOVE 240 TO PT-CLR
        WHEN FUNCTION MOD(DEATH-TIMER, 6) < 3
            MOVE "▚▞▚" TO PT-TEXT
            MOVE CLR-RED TO PT-CLR
        WHEN OTHER
            MOVE "▞▚▞" TO PT-TEXT
            MOVE CLR-BOMB TO PT-CLR
    END-EVALUATE
    PERFORM PUT-TEXT.

DRAW-GAME-OVER.
    MOVE CLR-RED TO PT-CLR
    MOVE 25 TO PT-COL
    MOVE "╔═════════════════════════════╗" TO PT-TEXT
    MOVE 9 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "║                             ║" TO PT-TEXT
    MOVE 10 TO PT-ROW  PERFORM PUT-TEXT
    MOVE 12 TO PT-ROW  PERFORM PUT-TEXT
    MOVE 14 TO PT-ROW  PERFORM PUT-TEXT
    MOVE 16 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "║      G A M E   O V E R      ║" TO PT-TEXT
    MOVE 11 TO PT-ROW  PERFORM PUT-TEXT
    MOVE SPACES TO PT-TEXT
    STRING "║     FINAL SCORE  " SCORE "     ║"
        DELIMITED BY SIZE INTO PT-TEXT
    MOVE 13 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "║    PRESS SPACE TO GO ON     ║" TO PT-TEXT
    MOVE 15 TO PT-ROW  PERFORM PUT-TEXT
    MOVE "╚═════════════════════════════╝" TO PT-TEXT
    MOVE 17 TO PT-ROW  PERFORM PUT-TEXT
    IF NEW-HI
        IF FUNCTION MOD(FRAME-COUNT, 16) < 10
            MOVE CLR-YELLOW TO PT-CLR
        ELSE
            MOVE CLR-WHITE TO PT-CLR
        END-IF
        MOVE "★ NEW HI-SCORE ★" TO PT-TEXT
        MOVE 14 TO PT-ROW  MOVE 32 TO PT-COL
        PERFORM PUT-TEXT
    END-IF.

*>  Split PT-TEXT into UTF-8 characters (the lead byte gives each
*>  one's length) and store one per cell from PT-ROW/PT-COL on.
PUT-TEXT.
    MOVE FUNCTION LENGTH(FUNCTION TRIM(PT-TEXT TRAILING)) TO PT-BYTES
    MOVE 1 TO PT-I
    MOVE PT-COL TO PT-C
    PERFORM UNTIL PT-I > PT-BYTES
        COMPUTE PT-B = FUNCTION ORD(PT-TEXT(PT-I:1)) - 1
        EVALUATE TRUE
            WHEN PT-B < 128 MOVE 1 TO PT-N
            WHEN PT-B < 224 MOVE 2 TO PT-N
            WHEN PT-B < 240 MOVE 3 TO PT-N
            WHEN OTHER      MOVE 4 TO PT-N
        END-EVALUATE
        IF PT-ROW >= 1 AND PT-ROW <= SCR-ROWS
           AND PT-C >= 1 AND PT-C <= SCR-COLS
           AND NOT (PT-SEE-THROUGH AND PT-TEXT(PT-I:1) = SPACE)
            MOVE PT-TEXT(PT-I:PT-N) TO CELL-CH(PT-ROW, PT-C)
            MOVE PT-N TO CELL-LEN(PT-ROW, PT-C)
            IF PT-SHADOW > 0 AND PT-TEXT(PT-I:PT-N) NOT = FULL-BLOCK
                MOVE PT-SHADOW TO CELL-CLR(PT-ROW, PT-C)
            ELSE
                MOVE PT-CLR TO CELL-CLR(PT-ROW, PT-C)
            END-IF
        END-IF
        ADD PT-N TO PT-I
        ADD 1 TO PT-C
    END-PERFORM
    MOVE 0 TO PT-SHADOW
    SET PT-SOLID TO TRUE.

*>  Turn GRID into one buffer of ANSI sequences and write it out.
*>  A colour code is only sent when it changes, and not for blanks.
EMIT-FRAME.
    ADD 1 TO FRAME-COUNT
    MOVE 1 TO OUT-PTR
    MOVE -1 TO CUR-CLR
    PERFORM VARYING R FROM 1 BY 1 UNTIL R > SCR-ROWS
        MOVE R TO ROW-NUM
        STRING ESC-CHAR "[" ROW-NUM ";1H"
            DELIMITED BY SIZE INTO OUT-BUF WITH POINTER OUT-PTR
        PERFORM VARYING C FROM 1 BY 1 UNTIL C > SCR-COLS
            IF CELL-CH(R, C)(1:1) NOT = SPACE
               AND CELL-CLR(R, C) NOT = CUR-CLR
                MOVE CELL-CLR(R, C) TO CUR-CLR CLR-NUM
                STRING ESC-CHAR "[38;5;" CLR-NUM "m"
                    DELIMITED BY SIZE INTO OUT-BUF WITH POINTER OUT-PTR
            END-IF
            MOVE CELL-CH(R, C)(1:CELL-LEN(R, C))
              TO OUT-BUF(OUT-PTR:CELL-LEN(R, C))
            ADD CELL-LEN(R, C) TO OUT-PTR
        END-PERFORM
    END-PERFORM
    STRING ESC-CHAR "[0m" DELIMITED BY SIZE INTO OUT-BUF
        WITH POINTER OUT-PTR
    PERFORM WRITE-OUT.
