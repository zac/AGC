# Apollo Guidance Computer (AGC) Engine

A cycle-accurate simulation of the Apollo Guidance Computer's core instruction set and timing written in Swift.

## Features

- Complete implementation of the AGC instruction set
- Accurate instruction timing and cycle counting
- Interrupt handling and vectoring
- Memory banking and addressing
- I/O channel simulation
- Support for Counter registers (TIME1-4, CDUX/Y/Z)

## Usage

The engine provides a low-level simulation of the AGC processor, including:

- Instruction execution and timing
- Memory access and banking
- I/O operations
- Interrupt processing
- Counter register updates

## Acknowledgements

Special thanks to the Virtual AGC project for their yaAGC implementation. The Swift implementation was made possible by the following resources:
- Website: https://virtualagc.github.io/
- GitHub: https://github.com/virtualagc/virtualagc

