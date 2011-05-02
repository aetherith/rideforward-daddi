'Main program

CON
  _CLKMODE = XTAL1 + PLL16X
  _CLKFREQ = 80_000_000

  RUNNING_LAMP_PIN = 0          'pin for running lamp (indicates when program is running)

  ADC_D_PIN  = 16               'serial pin (out) for ADC                                    
  ADC_C_PIN = 17                'clock pin for ADC
  ADC_S_PIN  = 18               'reset pin for ADC
  ADC_N_CHANNELS = 8            'number of ADC channels
  ADC_CHANNEL_MASK = %0000000011111111
                                'first eight bits enable differential mode; last eight enable channels
  ADC_N_SAMPLES = 5             'number of samples to average for each ADC measurement

  CAN_R_PIN = 19                'reset pin for CAN
  CAN_S_PIN = 20                'CS pin for CAN
  CAN_RX_PIN = 21               'SPI receive pin for CAN
  CAN_TX_PIN = 22               'SPI transmit pin for CAN
  CAN_C_PIN = 23                'SPI clock pin for CAN
  CAN_INT_PIN = 24              'interrupt pin for CAN
  CAN_RX0_PIN = 25              'RX0 buffer full pin for CAN
  CAN_RX1_PIN = 26              'RX1 buffer full pin for CAN
  CAN_FREQ = 20_000_000         'Frequency of CAN clock (external)

  KEY_PIN = 5                   'high when key is on
  CHARGER_PIN = 6               'high when charger is on

  FUEL_GAUGE_PIN = 15           'DAC pin for controlling fuel gauge circuit

  PSU_15_V_PIN = 2              'pin that turns off the 15 V power supples when high
  LCD_PWR_PIN = 3               'pin that turns on the LCD when high

  ZERO_WAIT_TIME = 1            'amount of time (s) to wait before measuring zero points
  ZERO_N_SAMPLES = 10           'number of samples to average for zero measurement of each channel

  I_BATT_CHANNEL = 0            'ADC channel for battery current sensor
  I_BATT_OFFSET = -3            'zero offset for battery curret sensor (bits)
  I_BATT_DEADBAND = 3           'deadband for battery current sensor (bits, +/-)
  I_BATT_SCALE_POS = 150_332    'conversion factor for battery current sensor, positive (uA / bit)
  I_BATT_SCALE_NEG = 150_332    'conversion factor for battery current sensor, negative (uA / bit)

  BATTERY_CHARGE_CAPACITY = 288_000_000
                                'total charge capacity (mA s) of battery pack
  CHARGE_RESET_PIN = 4          'hold this pin high to manually reset the battery charge to 100%

  STATE_KEY = 0                 'enumeration representing "key on" processing state
  STATE_CHARGER = 1             'enumeration representing "charger on" proessing state
  STATE_SLEEP = 2               'enumeration representing sleep state

OBJ
  ADC : "MCP3208"
  LCD : "LcdOutput"
  EEPROM : "Basic_I2C_Driver"
  CAN : "MCP2515-Example"

VAR
  word analog_zeros[ADC_N_CHANNELS]
  byte state
  long dt, last_cnt
  long test_message[4]
  long debug_stack[128]

PUB main
'' main method - repeatedly checks the state of key and charger and calls the appropriate
'' init and spin methods

  'cognew(debug, @debug_stack)

  init
  'dira[15]~~
  'dira[0]~~
  
  repeat
    case state
      STATE_KEY :
        'outa[0]~~
        'outa[15]~~
        if (ina[KEY_PIN])
          key_spin
        else
          state := STATE_SLEEP
          sleep
      STATE_CHARGER :
        'outa[0]~~
        'outa[15]~
        if (ina[CHARGER_PIN])
          charger_spin
        else
          state := STATE_SLEEP
          sleep
      STATE_SLEEP :
        'outa[0]~
        'outa[15]~~
        if (ina[KEY_PIN])
          state := STATE_KEY
          wake
          key_init
        elseif (ina[CHARGER_PIN])
          state := STATE_CHARGER
          wake
          charger_init

PUB measure_battery_current : i_batt
'' measures the main battery current (uA) once and integrates it into state of charge

  'get values from ADC
  i_batt := ADC.average(I_BATT_CHANNEL, ADC_N_SAMPLES) - analog_zeros[I_BATT_CHANNEL] + I_BATT_OFFSET
  if (||i_batt =< I_BATT_DEADBAND)
    i_batt := 0
    
  'scale values
  if (i_batt => 0)
    i_batt *= I_BATT_SCALE_POS
  else
    i_batt *= I_BATT_SCALE_NEG

  'integrate battery current and update state of charge
  'all of the powers of ten are to get good precision without exceeding POSX
  'TODO: check if precision can be increased
  long[@charge_remaining] := 0 #> (long[@charge_remaining] - i_batt / 1_000 * (dt / (clkfreq / 1_000_000)) / 1_000_000)

  'Update the state of charge in EEPROM
  EEPROM.WriteLong(EEPROM#BootPin, EEPROM#EEPROM, @charge_remaining, long[@charge_remaining])
   
  'Check for manual state of charge reset
  'TODO: make this more robust
  if (ina[CHARGE_RESET_PIN])
    long[@charge_remaining] := BATTERY_CHARGE_CAPACITY

  'update timing variables 
  dt := cnt - last_cnt
  last_cnt := cnt

PUB measure_analog_zeros | i
'' measures the zero values of the analog inputs

  'wait for readings to stabilize
  waitcnt(ZERO_WAIT_TIME * clkfreq + cnt)

  ' measure the zero points sequentially
  repeat i from 0 to ADC_N_CHANNELS - 1
    analog_zeros[i] := ADC.average(i, ZERO_N_SAMPLES)

PRI debug
  dira[RUNNING_LAMP_PIN]~~
  repeat
    !outa[RUNNING_LAMP_PIN]
    waitcnt(clkfreq / 4 + cnt)

PRI init
'' happens once when the program starts running (very rarely is this called;
'' under normal conditions the program never stops running)

  'prepare the EEPROM
  EEPROM.Initialize(EEPROM#BootPin)

  'prepare digital pins
  dira[PSU_15_V_PIN]~~
  dira[LCD_PWR_PIN]~~
  dira[RUNNING_LAMP_PIN]~~
  dira[CHARGE_RESET_PIN]~
  dira[KEY_PIN]~
  dira[CHARGER_PIN]~
  dira[12] := dira[13] := dira[14] := dira[15] := 1

  'start in sleep mode
  state := STATE_SLEEP
  sleep

PRI key_init
'' happens once each time the key is turned on

  'prepare the CAN controller
  CAN.Start(CAN_R_PIN, CAN_S_PIN, CAN_INT_PIN, CAN_RX0_PIN, CAN_RX1_PIN, CAN_RX_PIN, CAN_TX_PIN, CAN_C_PIN)
  CAN.SetCanRate(4)            
  CAN.OpenChannel(CAN#MODE_READONLY)

  'turn on the LCD
  outa[LCD_PWR_PIN]~~

  'start the LCD
  LCD.start

  'perpare the list of values we want to display on the LCD
  'do not change order!
  LCD.add_value(string("Battery Current"), string("Amp"))                       'ID = 0
  LCD.add_value(string("Charge Remaining"), string("%"))                        'ID = 1
  LCD.add_value(string("CAN Message ID"), string(" "))                          'ID = 2

PRI charger_init
'' happens once each time the charger is turned on

  'turn on the LCD
  outa[LCD_PWR_PIN]~~

  'start the LCD
  LCD.start

  'perpare the list of values we want to display on the LCD
  'do not change order!
  LCD.add_value(string("Charge Remaining"), string("%"))                        'ID = 0

PRI key_spin | i_batt
'' key spin loop - happens repeatedly as often as possible while key is on

  i_batt := measure_battery_current
   
  'output values to LCD
  LCD.set_value(0, i_batt / 1_000_000)               
  LCD.set_value(1, (long[@charge_remaining] / 1_000) * 100 / (BATTERY_CHARGE_CAPACITY / 1_000))
   
  'CAN testing
  if (CAN.ReceivePacket(@test_message) <> CAN#RXS_NOTHING_READY)
    LCD.set_value(2, test_message[0] >> 3)
  else
    LCD.set_value(2, 0)

  'fuel gauge testing
  outa[12] := outa[13] := outa[14] := outa[15] := 0
   
  'necessary to improve integral precision
  'may remove if the loop gets larger and slower in the future
  waitcnt(clkfreq / 200 + cnt)

PRI charger_spin
'' charger spin loop - happens repeatedly as often as possible while charger is on

  measure_battery_current

  'only display the charge remaining
  LCD.set_value(0, (long[@charge_remaining] / 1_000) * 100 / (BATTERY_CHARGE_CAPACITY / 1_000))
   
  'necessary to improve integral precision
  'may remove if the loop gets larger and slower in the future
  waitcnt(clkfreq / 200 + cnt)

PRI sleep
'' happens once each time we enter sleep mode (neither charger nor key is on)

  'reset timing variables
  dt := last_cnt := 0

  'stop all other cogs and peripherals
  ADC.stop
  CAN.CloseChannel
  CAN.SleepChannel
  CAN.Stop
  LCD.stop                                           
  LCD.clear_values
  
  'turn off power supplies to peripherals
  outa[PSU_15_V_PIN]~~
  outa[LCD_PWR_PIN]~
  outa[RUNNING_LAMP_PIN]~

  'go to slow clock
  clkset(%0_0_0_00_001, 20_000) '~20kHz no PLL
PRI wake
'' happens once each time we leave sleep mode
              
  'go to fast clock
  clkset(%0_1_1_01_001, 5_000_000) 'turn on PLL, but don't use it
  waitcnt(500 + cnt) 'wait 100us for PLL to stabilize
  clkset(%0_1_1_01_111, 80_000_000) '80MHz

  'prepare the ADC
  ADC.start(ADC_D_PIN, ADC_C_PIN, ADC_S_PIN, ADC_CHANNEL_MASK)

  'start EEPROM
  'measure the zero values of the analog inputs
  '(having just left sleep mode, the power supplies will be off)
  measure_analog_zeros

  'turn the sensor power supplies back on
  outa[PSU_15_V_PIN]~

DAT
  charge_remaining      long    BATTERY_CHARGE_CAPACITY
  testing               long    144_000_000