' Allows for numeric output to a frequency counter
' Basically a poor man's debugger

OBJ
  PWM : "PWMx8"

CON
  START_FREQ = 1000

PUB Start(pin)


PUB Print(pin, value)
  PWM.start(0, 1 << pin, START_FREQ)
  PWM.duty(pin, 128)