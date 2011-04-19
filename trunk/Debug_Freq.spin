' Allows for numeric output to a frequency counter
' Basically a poor man's debugger

OBJ
  PWM : "PWMx8"

VAR
  byte started

PUB Print(pin, number)
  if (!started)
    PWM.start(0, 1 << pin, number)
    PWM.duty(Pin, 128)
    started~~
  else
    PWM.set_freq(number)