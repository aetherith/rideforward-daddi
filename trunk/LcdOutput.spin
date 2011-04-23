'' outputs information to the serial LCD periodically
'' uses one cog

OBJ
  LCD : "SparkFun_Serial_LCD"

CON
  N_VALUES_MAX = 5              'maximum number of values to display
  UPDATE_FREQ = 20              'frequency (Hz) to update screen
  DISPLAY_TIME = 3              'amount of time (s) to display each value
  N_LINES = 2                   'number of lines
  N_COLS = 16                   'number of columns
  PIN = 1                       'output pin
  BAUD = 9_600                  'LCD serial communication speed (baud)

VAR
  byte names[N_VALUES_MAX * N_COLS]
  long values[N_VALUES_MAX]
  byte units[N_VALUES_MAX * 3]
  byte n_values

  byte cogno
  long stack[128] 'TODO optimize

'' starts the LCD printing on a new cog
PUB start
  LCD.init(PIN, BAUD, N_LINES, N_COLS)
  LCD.cls
  n_values := 0
  result := (cogno := cognew(print, @stack))

'' stops the LCD printing
PUB stop
  if (cogno)
    LCD.finalize
    cogstop(cogno)

'' adds a new value to the list of values to print
PUB add_value (name, unit)
  if (strsize(name) => N_COLS)
    bytemove(name, @names[n_values * N_COLS], N_COLS)
  else
    bytemove(name, @names[n_values * N_COLS], strsize(name))

  if (strsize(unit) => 3)
    bytemove(units, @units[n_values * 3], 3)
  else
    bytemove(units, @units[n_values * 3], strsize(units))

'' prints values to the LCD periodically
PRI print | value_no, timing
  repeat
    repeat value_no from 0 to n_values - 1
      timing := cnt
      repeat timing from timing to timing + clkfreq * DISPLAY_TIME step clkfreq / UPDATE_FREQ
        'LCD.cls
        'LCD.home
        'LCD.dec(value_no)
        'LCD.str(names[value_no * N_COLS])
        'LCD.gotoxy(0, 1)
        'LCD.dec(values[value_no])
        'LCD.gotoxy(13, 1)
        'LCD.str(units[value_no * N_COLS])
        waitcnt(timing)
       
    