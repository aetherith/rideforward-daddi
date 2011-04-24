'Main program

CON
  _CLKMODE = XTAL1 + PLL16X
  _CLKFREQ = 80_000_000

  RUNNING_LAMP_PIN = 0          'pin for running lamp (indicates when program is running)

  ADC_D_PIN  = 17               'serial pin (out) for ADC                                    
  ADC_C_PIN = 18                'clock pin for ADC
  ADC_S_PIN  = 19               'reset pin for ADC
  ADC_N_CHANNELS = 8            'number of ADC channels
  ADC_CHANNEL_MASK = %0000000011111111
                                'first eight bits enable differential mode; last eight enable channels
  ADC_N_SAMPLES = 5             'number of samples to average for each ADC measurement

  PSU_15_V_PIN = 2              'pin that turns off the 15 V power supples when high
  LCD_PWR_PIN = 3               'pin that turns on the LCD when high

  ZERO_PSU_OFF_TIME = 1         'amount of time (s) to keep sensor power supplies off before measuring zero points
  ZERO_N_SAMPLES = 10           'number of samples to average for zero measurement of each channel

  I_BATT_CHANNEL = 0            'ADC channel for battery current sensor
  I_BATT_OFFSET = -3            'zero offset for battery curret sensor (bits)
  I_BATT_DEADBAND = 3           'deadband for battery current sensor (bits, +/-)
  I_BATT_SCALE_POS = 150_332    'conversion factor for battery current sensor, positive (uA / bit)
  I_BATT_SCALE_NEG = 150_332    'conversion factor for battery current sensor, negative (uA / bit)

  BATTERY_CHARGE_CAPACITY = 288_000_000
                                'total charge capacity (mA s) of battery pack

OBJ
  ADC : "MCP3208"
  LCD : "LcdOutput"
  EEPROM : "Basic_I2C_Driver"

VAR
  word analog_zeros[ADC_N_CHANNELS]

PUB main | i_batt, dt, last_cnt
  ' running lamp is our first line of defense against bugs
  ' if the lamp is on, the program hasn't crashed
  dira[RUNNING_LAMP_PIN]~~
  outa[RUNNING_LAMP_PIN]~~

  'prepare the ADC
  ADC.start(ADC_D_PIN, ADC_C_PIN, ADC_S_PIN, ADC_CHANNEL_MASK)
  
  'perpare the list of values we want to display on the LCD
  'do not change order!
  LCD.start
  LCD.add_value(string("Battery Current"), string("Amp"))                       'ID = 0
  LCD.add_value(string("Charge Remaining"), string("%"))                        'ID = 1

  'prepare the EEPROM
  EEPROM.Initialize(EEPROM#BootPin)
                                                        
  'prepare digital pins
  dira[PSU_15_V_PIN]~~
  dira[LCD_PWR_PIN]~~

  'turn on the LCD
  outa[LCD_PWR_PIN]~~

  'measure the zero values of the analog inputs
  measure_analog_zeros

  'active loop
  repeat
    !outa[RUNNING_LAMP_PIN] 'flash running lamp so we know the loop is working and can tell if it's running really slow for some reason
    'get values from ADC
    i_batt := ADC.average(I_BATT_CHANNEL, ADC_N_SAMPLES) - analog_zeros[I_BATT_CHANNEL] + I_BATT_OFFSET
    if (||i_batt =< I_BATT_DEADBAND)
      i_batt := 0
      
    'scale values
    if (i_batt => 0)
      i_batt *= I_BATT_SCALE_POS
    else
      i_batt *= I_BATT_SCALE_NEG

    'output values to LCD
    LCD.set_value(0, i_batt / 1_000_000)               
    LCD.set_value(1, (long[@charge_remaining] / 1_000) * 100 / (BATTERY_CHARGE_CAPACITY / 1_000))

    'integrate battery current and update state of charge
    'all of the powers of ten are to get good precision without exceeding POSX
    'TODO: check if precision can be increased
    long[@charge_remaining] := 0 #> (long[@charge_remaining] - i_batt / 1_000 * (dt / (clkfreq / 1_000_000)) / 1_000_000)

    'Update the state of charge in EEPROM
    EEPROM.WriteLong(EEPROM#BootPin, EEPROM#EEPROM, @charge_remaining, long[@charge_remaining])    

    'necessary to improve integral precision
    'may remove if the loop gets larger and slower in the future
    waitcnt(clkfreq / 200 + cnt)

    'update timing variables 
    dt := cnt - last_cnt
    last_cnt := cnt

PUB measure_analog_zeros | i
'' measures the zero values of the analog inputs
                                                        
  '' turn off the sensor power supplies and wait for readings to stabilize
  outa[PSU_15_V_PIN]~~
  waitcnt(clkfreq * ZERO_PSU_OFF_TIME + cnt)

  '' measure the zero points sequentially
  repeat i from 0 to ADC_N_CHANNELS - 1
    analog_zeros[i] += ADC.average(i, ZERO_N_SAMPLES)

  '' turn the power supplies back on
  outa[PSU_15_V_PIN]~

DAT
  charge_remaining      long    288_000_000
  testing               long    144_000_000