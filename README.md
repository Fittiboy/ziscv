# ZISC-V
This is a simplified Assembler and Simulator for a small subset of the RV32I instruction set.

It runs on 128KiB of unified instruction and data memory.

## Why?
Just for Fun. No, Really.

[![justforfunnoreally.dev badge](https://img.shields.io/badge/justforfunnoreally-dev-9ff)](https://justforfunnoreally.dev)

## Building
### Zig version
The build is tested with Zig 0.16.0, but I personally use the `master` branch, so that I also make it work for that. The
long–term plan is 0.17.0 compatibility, once it releases. No promises past that.

### Build process
Run `zig build`, and you will find `ziscv-assembler` and `ziscv-simulator` in `./zig-out/bin/`.

You can choose an optimization mode with the `--release=[fast,small,safe]` option.

## Usage

### ziscv-assembler
Write a small Assembly program, using only the `add`, `sub`, `or`, `and`, `slt`, `addi`, `lw`, `sw`, and `beq`
instructions. Comments are allowed.

Register aliases, like `sp` or `s11` are supported, but you can of course use `x0, x1, …, x31` instead.
Note also that instructions and data share the same memory, and instructions are loaded starting at address `0x00000000`.
Trying to overwrite any of the instruction memory addresses is an error.

The program halts once it reaches the end of instruction memory. It does _not_ halt if you decide to jump past that point
deliberately. Halting happens when the program counter moves precisely one instruction beyond the final original
instruction. You may write a program that writes instructions into data memory, and simply jump there with `beq`. You can
then halt the program by jumping to the first address past instruction memory, to hit the halting condition.

Assuming the program is in `src/my_program.s` (try `src/hello.s`!), you then run
`./zig-out/bin/ziscv-assembler src/my_program.s > my_program.bin` to assemble the program into machine code.

### ziscv-simulator
Assuming you have a `my_program.bin` file ready, you simply run
`./zig-out/bin/ziscv-simulator my_program.bin > my_dump.bin` to run the program. The raw memory content as it as at
the end of the simulation is then dumped into stdout, and in this case redirected into `my_dump.bin`, ready to be
inspected with a hex viewer/editor of your choice!
