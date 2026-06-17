# ZISC-V
This is a simplified Assembler and Simulator for a small subset of the RV32I instruction set.

It runs on 128KiB of unified instruction and data memory.

## Why?
Just for Fun. No, Really.

[![justforfunnoreally.dev badge](https://img.shields.io/badge/justforfunnoreally-dev-9ff)](https://justforfunnoreally.dev)

## Building
### Zig version
I use the Zig master branch for educational projects like these, so the build script may break.
The plan is to update `build.zig` for version 0.17.0 when it comes out, if it is no longer compatible by then.

### Build process
Run `zig build`, and you will find `ziscv-assembler` and `ziscv-simulator` in `./zig-out/bin/`.

## Usage

### ziscv-assembler
Write a small Assembly program, using only the `add`, `sub`, `or`, `and`, `slt`, `addi`, `lw`, `sw`, and `beq`
instructions. Comments are allowed, but labels are not. Comments may only follow an instruction directly on the same
line, as each line is expected to be a valid instruction.

Okay:
```asm
addi x1, x0, -115 # This works just fine
```

Not okay:
```asm
# This will not parse
addi x1, x0, -115
```

Additionally, immediates are parsed only as simple base 10 literals.

Okay:
```asm
addi x1, x0, 32
```

Not okay:
```asm
addi x1, x0, 0x20
```

Register aliases, like `sp` or `s11` are not supported, use `x0, x1, …, x31` instead. Note also that instructions and
data share the same memory, and instructions are loaded starting at address `0x00000000`. Trying to overwrite any of the
instruction memory addresses is an error.

The program halts once it reaches the end of instruction memory. It does _not_ halt if you decide to jump past that point
deliberately. Halting happens when the program counter moves precisely one instruction beyond the final original
instruction. You may write a program that writes instructions into data memory, and simply jump there with `beq`. You can
then halt the program by jumping to the first address past instruction memory, to hit the halting condition.

Assuming the program is in `src/hello.S` (which is where a sample program actually sits!), you then run
`./zig-out/bin/ziscv-assembler src/hello.S > hello.bin` to assemble the program into machine code.

### ziscv-simulator
Assuming you have a `hello.bin` file ready (see the previous step!), you simply run
`./zig-out/bin/ziscv-simulator hello.bin > hello_dump.bin` to run the program. The raw memory content as it as at the end
of the simulation is then dumped into stdout, and in this case redirected into `hello_dump.bin`, ready to be inspected
with a tool such as `xxd`.
