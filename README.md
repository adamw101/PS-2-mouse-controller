#PS/2 mouse controller

## Overview
PS2_PMOD module implements a computer mouse controller.
It initializes and receives movement data from mouse using a PS/2 port.
Cursor position is calculated using the received data.
## Project Structure

```
├── hdl/
│ └── PS2_PMOD.vhd
├── tb/
│ └── PS2_PMOD_tb.vhd
└── README.md
```
## Tools & Technologies

- **HDL:** VHDL
- **FPGA:** ZYNQ XC7Z010(ZYBO Z7-10)
- **Toolchain:** AMD Vivado Design Suite
## About
This project was created as a part of the university course: Zaawansowane techniki programowania układów FPGA(ang. Advanced FPGA proggraming techniques ) at Warsaw University of Technology.
