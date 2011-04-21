'Main program

OBJ
  Debug : "Debug_Freq"
  ADC : "ADC_INPUT_DRIVER"
  LCD : "SparkFun_Serial_LCD"

CON
  _CLKMODE = XTAL1 + PLL16X
  _CLKFREQ = 80_000_000

  RUNNING_LAMP_PIN = 0
  DEBUG_FREQ_PIN   = 1
  LCD_TX_PIN       = 2
  LCD_BAUD         = 9_600

  MOSFET_PIN = 3
  
  ADC_DT_PIN  = 16
  ADC_IN_PIN  = 17
  ADC_CLK_PIN = 18
  ADC_RS_PIN  = 19

VAR
  byte i_batt_cog
  long i_batt_cog_stack[128]
  long offset_accumulator
  word offset

PUB Main
  ' lamp on P0 is our first line of defense against bugs
  ' if the lamp is on, the program hasn't crashed
  dira[RUNNING_LAMP_PIN]~~
  outa[RUNNING_LAMP_PIN]~~

  ' print main battery current
  i_batt_cog := cognew(Print_ADC(0, DEBUG_FREQ_PIN, 50), @i_batt_cog_stack)

  if (i_batt_cog == 1)
    outa[0]~
  else
    outa[0]~~

  repeat
    
PUB Print_ADC(channel, pin, freq)
  ' Periodically prints the specified ADC channel to the specified pin
  
  ' Initiate all the componants we will use (LCD and ADC objects)
  ADC.start(ADC_DT_PIN,ADC_IN_PIN,ADC_CLK_PIN,ADC_RS_PIN,2,1,12,1)
  LCD.init(LCD_TX_PIN,LCD_BAUD,2,16)
  LCD.cursor(0)                     'Turn the LCDs cursor off
  LCD.cls
  
  ' Turn the power supply off and take 5 readings of the zero point to average
  word offsetMin := 0
  word offsetMax := 0
  word cur_reading := 0
  dira[MOSFET_PIN]~~
  outa[MOSFET_PIN]~
  offsetMin := ADC.average_time(channel,1000/freq)
  offsetMax := offsetMin
  offset_accumulator := offsetMin
  repeat 4
    cur_reading := ADC.average_time(channel,1000/freq)
    offset_accumulator := offset_accumulator + cur_reading
    if(cur_reading < offsetMin)
      offsetMin := cur_reading
    if(cur_reading > offsetMax)
      offsetMax := cur_reading
    

  offset := offset_accumulator/5

  ' Turn the power supply back on
  outa[MOSFET_PIN]~~

  repeat
    LCD.home
    LCD.str(string("I: "))
    cur_reading := ADC.average_time(channel,1000/freq)
    if((cur_reading>offsetMin) and (cur_reading<offsetMax))
      LCD.dec(0)
    else
      LCD.dec(cur_reading-offset)
    LCD.gotoxy(0,1)
    LCD.str(string("I Offset: "))
    LCD.dec(offset)
  
  LCD.finalize

  {{
  Debug.Start(pin)
  Debug.Print(pin, 100)
  repeat
    Debug.Print(pin, 10)
    waitcnt(clkfreq + cnt)
    }}         