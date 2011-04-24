'' outputs information to the serial LCD periodically
'' uses one cog

CON
  N_VALUES_MAX = 5              'maximum number of values to display
  UPDATE_FREQ = 2               'frequency (Hz) to update screen
  DISPLAY_TIME = 3              'amount of time (s) to display each value
  N_LINES = 2                   'number of lines
  N_COLS = 16                   'number of columns
  N_UNITS_CHARACTERS = 3        'number of characters for units
  PIN = 1                       'output pin
  BAUD = 9_600                  'LCD serial communication speed (baud)

VAR
  byte names[N_VALUES_MAX * (N_COLS + 1)]
  long values[N_VALUES_MAX]
  byte units[N_VALUES_MAX * (N_UNITS_CHARACTERS + 1)]
  byte filler[N_COLS - N_UNITS_CHARACTERS + 1]
  byte n_values

  byte cogno
  long stack[128] 'TODO optimize

OBJ
  LCD : "SparkFun_Serial_LCD"

PUB start
'' starts the LCD printing on a new cog

  if (!cogno)
    result := (cogno := cognew(print, @stack))
  else
    result := cogno

PUB stop
'' stops the LCD printing

  if (cogno~)
    LCD.finalize
    cogstop(cogno)

PUB set_value (n, value) : success
'' changes one of the displayed values
  if (n < 0 or n > n_values)
    return false

  values[n] := value
  return true

PUB add_value (name, unit) : n
'' adds a new value to the list of values to print

  if (n_values == N_VALUES_MAX)
    return false
    
  if (strsize(name) => N_COLS)
    bytemove(@names[n_values * (N_COLS + 1)], name, N_COLS)
    bytefill(@names[n_values * (N_COLS + 1) + N_COLS], 0, 1)
  else
    bytemove(@names[n_values * (N_COLS + 1)], name, strsize(name))
    bytefill(@names[n_values * (N_COLS + 1) + strsize(name)], 32, N_COLS - strsize(name))
    bytefill(@names[n_values * (N_COLS + 1) + N_COLS], 0, 1)
  
  if (strsize(unit) => N_UNITS_CHARACTERS)
    bytemove(@units[n_values * (N_UNITS_CHARACTERS + 1)], unit, N_UNITS_CHARACTERS)
    bytefill(@units[n_values * (N_UNITS_CHARACTERS + 1) + N_UNITS_CHARACTERS], 0, 1)
  else
    bytefill(@units[n_values * (N_UNITS_CHARACTERS + 1)], 32, N_UNITS_CHARACTERS - strsize(unit))  
    bytemove(@units[n_values * (N_UNITS_CHARACTERS + 1) + (N_UNITS_CHARACTERS - strsize(unit))], unit, strsize(unit))
    bytefill(@units[n_values * (N_UNITS_CHARACTERS + 1) + N_UNITS_CHARACTERS], 0, 1)  
  ++n_values

  return n_values - 1

PRI print | value_no, timing
'' prints values to the LCD periodically

  bytefill(@filler[0], 32, N_COLS - N_UNITS_CHARACTERS)
  bytefill(@filler[N_COLS - N_UNITS_CHARACTERS], 0, 1)
  LCD.init(PIN, BAUD, N_LINES, N_COLS)
  LCD.cursor(0)
  LCD.cls
  repeat
    repeat value_no from 0 to n_values - 1
      repeat DISPLAY_TIME * UPDATE_FREQ
        timing := cnt
        LCD.home
        LCD.str(@names[value_no * (N_COLS + 1)])
        LCD.gotoxy(0, 1)
        LCD.str(@filler[0])
        LCD.gotoxy(0, 1)
        LCD.dec(values[value_no])
        LCD.gotoxy(13, 1)
        LCD.str(@units[value_no * (N_UNITS_CHARACTERS + 1)])
        waitcnt(clkfreq / UPDATE_FREQ + timing)
       
    