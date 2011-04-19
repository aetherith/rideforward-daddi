'Main program

OBJ
  Debug : "Debug_Freq"
  ADC : "ADC_INPUT_DRIVER"

CON
  _CLKMODE = XTAL1 + PLL16X
  _CLKFREQ = 80_000_000

  RUNNING_LAMP_PIN = 0
  DEBUG_FREQ_PIN   = 1
  
  ADC_DT_PIN  = 16
  ADC_IN_PIN  = 17
  ADC_CLK_PIN = 18
  ADC_RS_PIN  = 19

VAR
  byte i_batt_cog
  long i_batt_cog_stack[9]

PUB Main
  ' lamp on P0 is our first line of defense against bugs
  ' if the lamp is on, the program hasn't crashed
  dira[RUNNING_LAMP_PIN]~~
  outa[RUNNING_LAMP_PIN]~~

  ' print main battery current
  i_batt_cog := cognew(Print_ADC(0, DEBUG_FREQ_PIN, 50), @i_batt_cog_stack)

PUB Print_ADC(channel, pin, freq)
  ' periodically prints the specified ADC channel to the specified pin
  repeat
    Debug.Print(pin, ADC.average_time(channel, 1000 / freq))         