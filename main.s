@ ECE 372 Design Project # 1
@
@ Uses Registers: R0-R3 (Used for operations), R4 (Set LED data), R5 (Send Data to CLEARDATAOUT), R6 (Send Data to SETDATAOUT), R7 (Loop counter)
@
@ This program lights an LED (USER LED 3) on the BeagleboneBlack Board based on the ON_OFF_FLAG. The Flag is initially zero, but can be changed by a button push on GPIO1_30
@ which will cause an interrupt procedure that changes the flag to 1. The light will remain on as long as the Flag is set to 1.
@ If the flag is changed, USER LED 3 will turn off after a timer interrupt.
@   The Timer is based on a 32.678 KHz clock and it generates an interrupt every 2 seconds.
@
@ Written by Pranaw Bajracharya February 2026

.text
.global _start
.global INT_DIRECTOR
_start:

@ Setting the constants here so they are consistent throughout the program and easily adjustable.
.equ    CM_PER_GPIO1_CLKCTRL_ADDRESS, 0x44E000AC            @ Address for the GPIO1 clock control register, for turning on GPIO1
.equ    GPIO1_OE_ADDRESS, 0x4804C134                        @ Address for the GPIO1 output enable register, for setting USR LEDs as outputs
.equ    GPIO1_SETDATAOUT_ADDRESS, 0x4804C194                @ Address for the GPIO1 set data out register, for setting the logic of the USR LEDs
.equ    GPIO1_CLEARDATAOUT_ADDRESS, 0x4804C190              @ Address for the GPIO clear data out register, for clearing the logic of the USR LEDs

@ Honestly, these are a little redundant because they read just fine normally, but I like keeping the style consistent.
.equ    ONE_ENABLE_VALUE, 0x01                              @ Value for turning off bit IRQ and enabling various other modes.
.equ    TWO_ENABLE_VALUE, 0x02                              @ Value for enabling the GPIO clocks and various other modes.

@ LED Constants
.equ    USR3, 0x01000000                                    @ Value to light USR LED 3
.equ    USR2, 0x00800000                                    @ Value to light USR LED 2
.equ    USR1, 0x00400000                                    @ Value to light USR LED 1
.equ    USR0, 0x00200000                                    @ Value to light USR LED 0

@ GPIO Constants
.equ    GPIO1_FALLINGDETECT_ADDRESS, 0x4804C14C             @ Address of GPIO1_FALLINGDETECT register. Used for enabling detection of button press
.equ    GPIO1_IRQSTATUS_SET_0_ADDRESS, 0x4804C034           @ Address of GPIO1_IRQSTATUS_SET_0 register. Used for enabling GPIO IRQ requests on POINTRPEND1
.equ    GPIO_IRQSTATUS_0_ADDRESS, 0x4804C02C                @ Address of GPIO_IRQSTATUS_0 register. Used for determining whether the button push triggered the IRQ request and to turn off GPIO1_30 interrupt requests.

.equ    BIT_TWO, 0x00000004                                 @ Value used to obtain the 2nd bit in the various INT registers.
.equ    BIT_SEVEN, 0x00000080                               @ Value used for setting the seventh bit of the CPSR
.equ    BIT_THIRTY, 0x40000000                              @ Value used to obtain the GPIO1_30 bit in various GPIO1 uses

@ Timer Constants
.equ    BIT_THIRTY_TWO, 0x80000000                          @ Value to enable TIMER7 interrupts in the INTC
.equ    CM_PER_TIMER7_CLKCTRL_ADDRESS, 0x44E0007C           @ Address of the CM_PER_CLKCTRL register. Used to enable the clock for the TIMER7 module
.equ    PRCM_CLKSEL_TIMER7_CLK_ADDRESS, 0x44E00504          @ Address of the PRCM CLKSEL_TIMER7_CLK register. Used to set the multiplexer for a 32.768 KHz clock to TIMER7
.equ    TIMER7_OCP_CFG_ADRESS, 0x4804A010                   @ Address of the TIMER7 Configuration register. Used to reset the Timer7 module.
.equ    TIMER7_TCRR_ADDRESS, 0x4804A03C                     @ Address of the TIMER7 Count register. Used to store count value until overflow
.equ    TIMER7_TLDR_ADDRESS, 0x4804A040                     @ Address of the TIMER7 Load register. The value of this register is loaded into the TIMER7 count register at the start after overflow
.equ    TLDR_VALUE, 0xFFFF0000                              @ Value within the TIMER 7 TLDR register. Determines timer overflow interval; Interval Time = (0xFFFFFFFF - TLDR + 1)(Clock Period)(Clock Divider). The PS or clock divider is 1 in our case

@ Interrupt Constants
.equ    INTC_CONTROL_ADDRESS, 0x48200048                    @ Address of INTC_CONTROL register. Used to disable NEWIRQ bit so that the processor can respond to new IRQ.
@       GPIO
.equ    INTC_MIR_CLEAR3_ADDRESS, 0x482000E8                 @ Address of INTC_MIR_CLEAR3 register. Used to unmask INTC INT 98, GPIOINT1A
.equ    INT_PENDING_IRQ3_ADDRESS, 0x482000F8                @ Address of INT_PENDING_IRQ3 register. Used to determine whether the interrupt signal came from GPIOINT1A
@       Timer
.equ    INTC_MIR_CLEAR2_ADDRESS, 0x482000C8                 @ Address of INTC_MIR_CLEAR2 register. Used to unmask INTC INT 95, TINT7
.equ    INT_PENDING_IRQ2_ADDRESS, 0x482000D8                @ Address of INT_PENDING_IRQ2 register. Used to determine whether the interrupt signal came from TIMER7.
.equ    TIMER7_IRQ_ENABLE_SET_ADDRESS, 0x4804A02C           @ Address of the TIMER7 IRQ_ENABLE_SET register. Used to enable IRQ requests during a counter overflow.
.equ    TIMER7_IRQ_STATUS_ADDRESS, 0x4804A028               @ Address of the TIMER7 IRQ register. Used to turn the TIMER7 IRQ off so we can send additional IRQ requests.


@ Initializing the Stacks
STACK_SETUP:
    LDR R13,=STACK1                                         @ Point to the base of the STACK for SVC mode
    ADD R13, R13, #0x1000                                   @ Point to the TOP of the stack
    CPS #0x12                                               @ Switch to IRQ mode
    LDR R13,=STACK2                                         @ Point to IRQ stack's base
    ADD R13, R13, #0x1000                                   @ Point to the TOP of the stack
    CPS #0x13                                               @ Switch back to SVC mode


@ Turns on GPIO1
GPIO_ENABLE:
    MOV R0, #TWO_ENABLE_VALUE                               @ Value to enable clock for a GPIO module
    LDR R1,=CM_PER_GPIO1_CLKCTRL_ADDRESS                    @ Loads the address of the GPIO1 clock control register into R1
    STR R0, [R1]                                            @ Writes the enable clock value into the GPIO1 clock control register


@ Enables the BeagleBone Black's USR LEDs as outputs
GPIO1_OUTPUT_ENABLE:
    LDR R0,=0xFE1FFFFF                                      @ Load word to program GPIO1's USR LEDs as outputs (GPIO1_21, GPIO1_22, GPIO1_23, GPIO1_24) into R0
    LDR R1,=GPIO1_OE_ADDRESS                                @ Load in address of GPIO1_OE address into R1

    LDR R2, [R1]                                            @ READ the GPIO1_OE register into R2
    AND R2, R2, R0                                          @ MODIFY the read-in value in R2 with R0, and then place back into R2
    STR R2, [R1]                                            @ WRITE the modified value from R2 to the location at R1.

    LDR R5,=GPIO1_CLEARDATAOUT_ADDRESS                      @ Load in GPIO1_CLEARDATAOUT register address into R5
    LDR R6,=GPIO1_SETDATAOUT_ADDRESS                        @ Load in GPIO1_SETDATAOUT register address into R6


@ GPIO interrupt requests
IRQ_GPIO_Initialization:
@ Detect falling edge on GPIO1_30 and enable to assert POINTRPEND1.
    LDR R1,=GPIO1_FALLINGDETECT_ADDRESS                     @ Loads in GPIO1_FALLINGDETECT register address into R1
    MOV R2, #BIT_THIRTY                                     @ Moves the value for Bit 30 into R2
    LDR R3, [R1]                                            @ Reads the value of the GPIO1_FALLINGDETECT register into R3.
    ORR R3, R3, R2                                          @ Modifies the read in value (set bit 30)
    STR R3, [R1]                                            @ Writes the value back into the GPIO1_FALLINGDETECT register
    LDR R1,=GPIO1_IRQSTATUS_SET_0_ADDRESS                   @ Loads the value of GPIO1_IRQSTATUS_SET_0 address into R1.
    STR R2, [R1]                                            @ Writes the 7th bit in GPIO1_IRQSTATUS_SET_0, enabling GPIO1_30 request on POINTRPEND1


@ Initialize INTC
INTC_INITIALIZATION:
    @ Resets INTC
    MOV R0, #TWO_ENABLE_VALUE
    LDR R1,=0x48200010
    STR R0, [R1]

   @ Unmasks INTC INT # 95, TINT7
    LDR R1,=INTC_MIR_CLEAR2_ADDRESS                            @ Loads in the INTC_MIR_CLEAR2 register address.
    LDR R2,=BIT_THIRTY_TWO                                    @ Moves the value for Bit 32 into R2; this is used to unmask INTC 95, TINT7
    STR R2, [R1]                                           @ Write the Bit 32 value into the INTC_MIR_CLEAR2 register

    @ Unmasks INTC INT # 98, GPIOINT1A
    LDR R1,=INTC_MIR_CLEAR3_ADDRESS                         @ Loads in the INTC_MIR_CLEAR3 register address.
    MOV R2,#BIT_TWO                                         @ Moves the value for Bit 2 into R2, this is used to unmask INTC 98, GPIOINT1A
    STR R2, [R1]                                            @ Write the Bit 2 value into the INTC_MIR_CLEAR3 register

   @ Hooking the system's IRQ vector
   @ I tried just modifying the startup_ARMCA8.S but I just ran into so many random issues.
   @ This worked more consistently.
@    LDR R1,=0x4030CE38                                      @ Address of first instruction in SYS_IRQ procedure
@    LDR R2, [R1]                                            @ Read SYS_IRQ address
@    LDR R3,= SYS_IRQ                                        @ Address where SYS_IRQ address will be saved
@    STR R2, [R3]                                            @ Saving SYS_IRQ address to use if not our IRQ
@    LDR R2,= INT_DIRECTOR                                   @ Load address of our INT_DIRECTOR
@    STR R2, [R1]                                            @ Store in SYS_IRQ first address location in literal. Effectively replacing SYS_IRQ with INT_DIRECTOR


@ Turns on TIMER7 and sets it up for a 32.768 KHz clock signal
TIMER7_ENABLE:

    @ Timer2 OFF - I am not sure why but timer2 is automatically enabled on my device and the 32 KHz signal there as well
    MOV R0, #0x30000    @ Default value
    LDR R1,=0x44E00080
    STR R0, [R1]

    MOV R0, #0x0
    LDR R1,=0x44E00508
    STR R0, [R1]

    @ Turning on the clock module
    MOV R0, #TWO_ENABLE_VALUE                               @ Value to enable TIMER7 clock
    LDR R1,=CM_PER_TIMER7_CLKCTRL_ADDRESS                   @ Loads the address of the TIMER7 clock control register into R1
    STR R0, [R1]                                            @ Writes the enable clock value into the TIMER7 clock control register


    @ Selecting the 32.768 KHz clock signal
    MOV R0, #TWO_ENABLE_VALUE                               @ Value to select the 32.768 KHz signal in the multiplexer
    LDR R1,=PRCM_CLKSEL_TIMER7_CLK_ADDRESS                  @ Loads the address of TIMER7's PRCM clock select register.
    STR R0, [R1]                                            @ Writes the 32.768 KHz select value into the PRCM clock select register


    @ Resets Timer
    MOV R0, #ONE_ENABLE_VALUE                               @ Value to reset TIMER7
    LDR R1,=TIMER7_OCP_CFG_ADRESS                           @ Loads the address of TIMER7's configuration register.
    STR R0, [R1]                                            @ Writes the value to reset the timer module

    @ Enables Overflow IRQ
    MOV R0, #TWO_ENABLE_VALUE                               @ Value to enable TIMER7 interrupt generation
    LDR R1,=TIMER7_IRQ_ENABLE_SET_ADDRESS                   @ Loads the address of TIMER7's IRQ_ENABLE_SET register.
    STR R0, [R1]                                            @ Writes the value to enable TIMER7 IRQ requests into the IRQ_ENABLE_SET register.

    @ Sets up Timer Load and Count registers
    LDR R0,=TLDR_VALUE                                      @ Value that causes count register to overflow every two seconds
    LDR R1,=TIMER7_TLDR_ADDRESS                             @ Loads the address of the Timer7 Load register into R1
    STR R0, [R1]                                            @ Stores the TLDR value for 2 second intervals in to the Timer 7 load register
    LDR R1,=TIMER7_TCRR_ADDRESS                             @ Loads the address of the Timer7 Count register into R1
    STR R0, [R1]                                            @ Stores the TLDR value into the Timer7 Count register for the initial count

    @   Starts the count
    MOV R0, #ONE_ENABLE_VALUE
    LDR R1,=0x4804A038
    STR R0, [R1]


@ Make sure that the processor IRQ enabled in CPSR
IRQ_ENABLE:
    MRS R3, CPSR                                            @ Copies the CPSR to R3
    BIC R3,#BIT_SEVEN                                       @ Clears bit 7
    MSR CPSR_c, R3                                          @ Writes back to the CPSR, only modifying the lower eight bits


@ Program's Main Logic. Loops indefinitely
LIGHT_LOOP: NOP
    B LIGHT_LOOP                                            @ Infinite cycle


@ Handles interrupts
INT_DIRECTOR: STMFD SP!, {R0-R3, LR}                        @ Push registers onto the stack


   @ GPIO Check
@   LDR R0,=INT_PENDING_IRQ3_ADDRESS                        @ Address of INTC_PENDING_IRQ3 register
@   LDR R1, [R0]                                            @ Read in value from INTC_PENDING_IRQ3 register
@   TST R1, #BIT_TWO                                        @ TEST BIT 2,
@   BEQ PASS_ON                                             @ Means signal is not from GPIOINT1A, go back to wait loop, else:


    @ Button Check
    LDR R0,=GPIO_IRQSTATUS_0_ADDRESS                        @ Load GPIO1_IRQSTATUS_0 register address
    LDR R1, [R0]                                            @ Read in value of STATUS register
    TST R1, #BIT_THIRTY                                     @ Check if bit 30 = 1
    BNE BUTTON_SVC                                          @ If bit 30 == 1, then button pushed
                                                           @ If bit == 0, then go to next line
    @ Timer Check
    LDR R0,=INT_PENDING_IRQ2_ADDRESS                        @ Address of the INT_PENDING_IRQ2 register
    LDR R1, [R0]                                            @ Read in value from INT_PENDING_IRQ2 register
    TST R1, #BIT_THIRTY_TWO                                 @ TEST BIT 32
    BNE FLAG_CHECK_SEND                                     @ If bit 32 == 1, then timer overflow, must service LED
                                                           @ If bit 32 == 0, then go next line

PASS_ON:
    LDMFD SP!, {R0-R3, LR}                                  @ Restore the registers on INT exceit
    SUBS PC, LR, #4                                         @ Return to Program Loop


BUTTON_SVC:
    MOV R1, #BIT_THIRTY                                     @ The value that will turn off GPIO1_30 interrupt request/INTC interrupt request.
    STR R1, [R0]                                            @ Write to GPIO1_IRQSTATUS_0 register.

    @ Turns of NEWIRQ so that the processor can respond to new IRQs
    LDR R0,=INTC_CONTROL_ADDRESS                            @ Load address of INTC_CONTROL register,
    MOV R1, #ONE_ENABLE_VALUE                               @ Value to clear bit 0, allowing for new interrupts.
    STR R1, [R0]                                            @ Write Data to INT_CONTROL register

    @ Toggles the value of the flag.
    LDR R0,=ON_OFF_FLAG                                     @ Loads the address of the flag into R0
    LDR R1, [R0]                                            @ Loads the value of the flag into R1
    EOR R1, R1, #0x1                                        @ EOR's itself with 1 to toggle between 1 and zero
    STR R1, [R0]                                            @ Stores the new flag value in memory

    LDMFD SP!, {R0-R3, LR}                                  @ Restore the registers on INT exit
    SUBS PC, LR, #4                                         @ Return to Program Loop


@ Tests the flag and writes the LED logic to GPIO1_SETDATAOUT
FLAG_CHECK_SEND: NOP                                                   @ NOP for breakpoint. Does nothing.
    @ Turn off Timer Interrupt
    LDR R0,=TIMER7_IRQ_STATUS_ADDRESS                       @ Load address of TIMER7_IRQ_STATUS register
    MOV R1, #TWO_ENABLE_VALUE                               @ Loads the value to clear the IRQ STATUS
    STR R1, [R0]                                            @ Writes the enable value to the TIMER7_IRQ_STATUS register

    @ Flag Check
    LDR R0,=ON_OFF_FLAG                                     @ Gets the address of the flag
    LDR R1, [R0]                                            @ Loads the value of the flag
    TST R1, #1                                              @ Checks to see if the flag is on
    BEQ USR_OFF                                             @ If the flag is not on, Turn OFF
                                                           @ Else, go to next line

USR3_ON:
    MOV R4, #USR3                                           @ Loads the value to light USR3 into register 4
    STR R4, [R6]                                            @ Write to the GPIO1_SETDATAOUT register with the current LED value (in R4)
    MOV PC, R14                                             @ Return to calling program using return address in R14



@ Turns off all of the USR LEDs
USR_OFF:
    MOV R4, #0xFFFFFFFF                                     @ Load in word that will set all the USR LEDs OFF (we are writing to *clear* data out, so 1 results in OFF)
    STR R4, [R5]                                            @ Write to the GPIO1_CLEARDATAOUT register with the current LED value (in R4)
    MOV PC, R14                                             @ Return to calling program using return address in R14


DONE: NOP                                                   @ Nothing happens here, the program just ends. Due to the light loop. The program shouldn't reach this.


STACK_AND_ALIGNMENT:
.align 2
SYS_IRQ: .WORD 0                                            @ Location of the System IRQ Address
.data

ON_OFF_FLAG: .byte  0x0                                     @ Sets aside a byte of memory for the flag. We don't need this much but we got weird stack errors once due to alignment and I don't really want to deal with that right now.

.align 2
STACK1: .rept 1024                                          @ Stack for SVC Mode
      .word 0x0000
      .endr
STACK2: .rept 1024                                          @ Stack for IRQ Mode
      .word 0x0000
      .endr

.END




