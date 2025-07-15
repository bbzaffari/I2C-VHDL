# I2C Driver (VHDL)

This project implements an I²C driver (`driver_i2c`) in VHDL, developed for the Integrated Systems Design II course at PUCRS.

The module handles read and write operations using a finite state machine, working with a 50 MHz clock and generating I²C signals with SCL up to 100 kHz. SDA is bidirectional.

I didn’t finish all the tests yet, so this version focuses mainly on the core logic and synthesis setup.
