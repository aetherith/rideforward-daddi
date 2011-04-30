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
  CHARGE_RESET_PIN = 4          'hold this pin high to manually reset the battery charge to 100%

  KEY_PIN = 6                   'high when key is turned on
  CHARGER_PIN = 7               'high when charger plugged in & charging

OBJ
  ADC : "MCP3208"
  LCD : "LcdOutput"
  EEPROM : "Basic_I2C_Driver"
  CAN : "MCP2515-Example"

VAR
  word analog_zeros[ADC_N_CHANNELS]
  byte test_message[4]
  byte SLEEPING
  byte CHARGER
  byte KEY

PUB main | i_batt, dt, last_cnt, i 
  ' running lamp is our first line of defense against bugs
  ' if the lamp is on, the program hasn't crashed
  dira[RUNNING_LAMP_PIN]~~
  outa[RUNNING_LAMP_PIN]~~

  'prepare the ADC
  ADC.start(ADC_D_PIN, ADC_C_PIN, ADC_S_PIN, ADC_CHANNEL_MASK)

  'prepare the EEPROM
  EEPROM.Initialize(EEPROM#BootPin)
                                                        
  'prepare digital pins
  dira[PSU_15_V_PIN]~~
  dira[LCD_PWR_PIN]~~       
  dira[CHARGE_RESET_PIN]~
  dira[KEY_PIN]~
  dira[CHARGER_PIN]~

  'Main loop of the program
  repeat
    KEY := ina[KEY_PIN]
    CHARGER := ina[CHARGER_PIN]
    if (CHARGER == 1)
      if (SLEEPING == 1)
        'Bring COG0 back up to full speed
        _rcslow_to_full_speed
        'prepare the ADC
        ADC.start(ADC_D_PIN, ADC_C_PIN, ADC_S_PIN, ADC_CHANNEL_MASK)
        SLEEPING := 0
        
     'measure the zero values of the analog inputs
      measure_analog_zeros

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

        'necessary to improve integral precision
        'may remove if the loop gets larger and slower in the future
        waitcnt(clkfreq / 200 + cnt)

        'update timing variables 
        dt := cnt - last_cnt
        last_cnt := cnt
      while(CHARGER == 1)
      
    elseif (KEY == 1)
      if(SLEEPING == 1)
        'Bring COG0 back up to full speed
        _rcslow_to_full_speed
        'prepare the ADC
        ADC.start(ADC_D_PIN, ADC_C_PIN, ADC_S_PIN, ADC_CHANNEL_MASK)
        'Wake up the CAN controller perhaps at some point flip a pin that goes to the transmitter to turn it back on
        CAN.WakeChannel
        SLEEPING := 0

      'prepare the CAN controller driver
      CAN.Start(CAN_R_PIN, CAN_S_PIN, CAN_INT_PIN, CAN_RX0_PIN, CAN_RX1_PIN, CAN_RX_PIN, CAN_TX_PIN, CAN_C_PIN)
      CAN.SetCanRate(2)
      CAN.OpenChannel(CAN#MODE_READWRITE)

      'CAN test
      repeat i from 0 to 3
        test_message[i] := i
      CAN.SendPacket(100, 4, @test_message)

      'perpare the list of values we want to display on the LCD
      'do not change order!
      LCD.start
      LCD.add_value(string("Battery Current"), string("Amp"))                       'ID = 0
      LCD.add_value(string("Charge Remaining"), string("%"))

      'turn on the LCD
      outa[LCD_PWR_PIN]~~

      'measure the zero values of the analog inputs
      measure_analog_zeros
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

        {{Here is where we will need to include the CAN read code.  I still need to puzzle through the driver and the controller's info before I can write this}}

          

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
      while(KEY == 1)
    if(SLEEPING == 0)
      CAN.SleepChannel
      CAN.Stop
      ADC.stop
      'turn off the LCD
      outa[LCD_PWR_PIN]~
      'Turn off unneeded cogs as I believe we only need one for the stuff we will be running
      for i from 1 to 7
        cogstop(i)
      _to_rcslow_speed
     ''turn off the sensor power supplies
      outa[PSU_15_V_PIN]~~
      SLEEPING := 1



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

PRI _rcslow_to_full_speed
'' put propeller into a fast speed (80MHz), intended to be used after propeller was put in slow mode

  clkset(%0_1_1_01_010, 5_000_000) ' turn on PLL, but don't use it
  waitcnt(500 + cnt) ' wait 100us for PLL to stabilize
  clkset(%0_1_1_01_111, 80_000_000) ' 80MHz

PRI _to_rcslow_speed
'' put propeller into slowest power save speed (using internal oscilator)

  clkset(%0_0_0_00_001, 20_000) ' ~20kHz no PLL

DAT
  charge_remaining      long    BATTERY_CHARGE_CAPACITY
  testing               long    144_000_000