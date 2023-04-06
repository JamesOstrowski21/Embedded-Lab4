;
; Lab 4.asm
;
; Created: 3/28/2023 12:05:42 PM
; Authors : James Ostrowski and Kai Lindholm 
;

.include "m328Pdef.inc"
.cseg

;
.org 0x0000
	rjmp RESET

.org 0x0002				; Toggle Fan State 
	rjmp INT0_vect

.org 0x0006				; Update Duty Cycle 
	rjmp PCINT0_INT 

.org 0x0020				; TOV0 interrupt
	rjmp TOV0_INT


.def	drem8u	= r26		;remainder
.def	dres8u	= r27		;result
.def	dd8u	= r27		;dividend
.def	dv8u	= r28		;divisor

.def temp = r18
.def value = r20		; Current value of rpg, used to calc duty cycle
.def input = r22		; State of the rpg 	
.def prevInput = r21
.def fanBool = r19		; state of the fan 
.def update = r24
.def delayLength = r23
.def rpgInterruptCount = r25
.def prevValue = r15
.def tempUpdate = r17
rjmp RESET

msg1: .db "DC = ", 0x00
msg2: .db "Fan = ON ", 0x00, 0
msg3: .db "Fan = OFF", 0x00
msg4: .db " % ", 0x00

RESET:
	cli
	ldi		temp, LOW(RAMEND)
	out		SPL, temp
	ldi		temp, HIGH(RAMEND)
	out		SPH, temp
	
	ldi		fanBool, 0			; fans initial state is off
	ldi		update, 0
	clr		prevValue
	ldi		prevInput, 0x03		; inital state of RPG is 11
	
;---------------------PIN CONFIGURATION-------------------------------------
	clr		r16							
	ldi		r16, (1<<DDB3) | (1<<DDB4) |(1<<DDB5)		; set pins 3 and 5 as outputs for the LCD
	out		DDRB, r16
	
	ldi		temp, (1<<PB2) | (1<<PB4) | (1<<PB3)
	out		PORTB, temp					; enable pullups 				
	ldi		temp, (1<<PD2)
	out		PORTD, temp					; enable pullups 
	
	ldi		temp, (1<<PD3)
	out		DDRD, temp					; enable OCRB output 
	
;-------------------- Setup pin interrupts ---------------------------------
	// INT0	- PB  interrupt	
	ldi		temp, (1<<ISCO1)				; enable INT0 interrupts on falling edge
	sts		EICRA, temp

	ldi		temp, (1<<INT0)					; enables int0 flag. 
	out		EIMSK, temp
	
	// PCINT0-1 - RPG interrupts
	ldi		temp, (1<<PCIE0)				; interrupts on Pin change interrupt 0
	sts		PCICR, temp

	ldi		temp, (1<<PCINT0) | (1<<PCINT1)			; enable specific interrupts on PCINT0
	sts		PCMSK0, temp

;--------------- Initialize Timer/Counter for fast PWM mode --------------
	ldi		temp,  (1<<COM2B1) |(1<<WGM21) | (1<<WGM20)
	sts		TCCR2A, temp								; set to fast non-inverting PWM mode

	ldi		temp,  (1 << WGM22) |(1 << CS20) 
	sts		TCCR2B, temp								; set the OC2RA as TOP and 1-prescaling

	ldi		temp, 200								; TOP value, 201 total steps ~79.6KHz freq 
	sts		OCR2A, temp			
			
	ldi		value, 0								; Set the starting duty cycle
	mov		temp, value
	sts		OCR2B, temp

;-------------- Enable T/C0 for delays -----------------------------------
	ldi		temp, (1<<CS01) | (1<<CS00)
	out		TCCR0B, temp	; Timer clock = system clock / 64

;------------------ Initalize the LCD ------------------------------------
rcall LCDinit
rcall updateDC
rcall fanOFF

sei
main: 
	sbrc	update, 0			; check if an update flag is set. 
	rjmp	ToggleFan
	sbrc	update, 1
	rjmp	incrementDC
	sbrc	update, 2
	rjmp	decrementDC
	
	rjmp	main				; if not repeat
;----------------- Interrupt Service Routines ---------------------------
	
INT0_vect: 
	ldi		temp, SREG		; save state of SREG
	push		temp
	
	cli 
	
	ldi		update, 0x01
	ldi		temp, 0x01
	eor		fanBool, temp		; flip the state of the fan. if off turn on, if on turn off

	rjmp		intDONE	
	
TOV0_INT:
	ldi		temp, SREG		; save state of SREG
	push		temp
	
	cli 
	
	ldi		temp, (1 << TOV0)
	out		TIFR0, temp		; Reset TOV0
	
	rjmp		intDONE		
		 
PCINT0_INT:
	ldi		temp, SREG		; save state of SREG
	push		temp
	
	cli
	
	in		input, PINB
	andi		input, 0x03		; mask out PINA and PINB

	inc		rpgInterruptCount
	cpi		rpgInterruptCount, 1
	breq		firstTime

	cpi		rpgInterruptCount, 4 	; if the rpg is back at the idle state 
	breq		DONE
	rjmp		intDONE

DONE: 
	;mov		update, tempUpdate
	clr		rpgInterruptCount
	rjmp	intDONE

firstTime:
	cpi		input, 0x01		; save the inital state change on the pins
	breq	rpgCW
	cpi		input, 0x02
	breq	rpgCCW

	rjmp	intDONE

rpgCW: 
	ldi		update, 0x02		; if the rpg is moving CW, update bit 2
	rjmp	intDONE
	
rpgCCW: 
	ldi		update, 0x04		; if the rpg is moving CCW,update bit 3
	rjmp	intDONE
	
intDONE:
	pop temp
	out SREG, temp	; return the state of the SREG
	sei 
	reti
;------------------- main subroutines -----------------

incrementDC:
	cli					; critial code 
	clr		update			; reset updates. 

	cpi		value, 200		; check if the DC is at its max, if so don't allow more increasing. 
	breq	incDone

	ldi		temp, 2
	add		value, temp		; increment DC by 1%
	
incDone:
	sts		OCR2B, value	
	
	// update DC 
	rcall	updateDC
	rcall	fanON
	
	sei					; renable interrupts 
	rjmp	main

decrementDC:
	cli					; critial code 
	clr		update

	cpi		value, 0		; don't allow DC to decrement past 0. 
	breq	decDone

	ldi		temp, 2
	sub		value, temp		; decrease DC by 1 %
decDone: 
	sts		OCR2B, value	
		
	// update DC
	rcall	updateDC
	rcall	fanON
	
	sei
	rjmp	main
  
ToggleFan:
	clr	update		
	cpi fanBool, 1 		; if fan needs to turn on.
	breq turnFanOn
	cpi fanbool, 0		; if fan needs to turn off. 
	breq turnFanOff

	rjmp main

turnFanOff:
	mov		prevValue, value  ; store the current state of value

	ldi		value, 0
	cli
	rcall	updateDC			; update DC with a value of 0 
	rcall	fanOFF				; add fan off on second line 
	sei
	
	sts		OCR2B, value			; turn fan off by setting duty cycle to 0 
	mov		value, prevValue	; move back value

	ldi		temp, 0x00		; turn RPG interrupts off. Keep button interrupts.
	sts		PCMSK0, temp

	rjmp	main

turnFanOn: 
	cli
	rcall	updateDC			; set back the duty cycle from value. 
	rcall	fanON
	sei 
		
	sts		OCR2B, value		

	ldi		temp, 0x03		; turn RPG control back on
	sts		PCMSK0, temp

	rjmp	main

updateDC:
	cbi PORTB, PB5 ; Set RS to 0 for command codes
	ldi r17, 0x00	;upper nibble of 0x01 which clears display
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x01 ; lower nibble of clear display
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x00 ; upper nibble of return home
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x02 ;lower nibble of return home
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	sbi PORTB, PB5 ;set RS back to 1 for character display 
	ldi r24, 5
	ldi r30,LOW(2*msg1) ; Load Z register low
    ldi r31,HIGH(2*msg1) ; Load Z register high
    rcall displayCString	
	rcall displayDC
	ldi r24, 3
	ldi r30,LOW(2*msg4) ; Load Z register low
    ldi r31,HIGH(2*msg4) ; Load Z register high
    rcall displayCString
	ret

fanON:
	rcall SecondLine
	ldi r24, 9
	ldi r30,LOW(2*msg2) ; Load Z register low
    ldi r31,HIGH(2*msg2) ; Load Z register high
	rcall displayCString
	ret

fanOFF:
	rcall SecondLine
	ldi r24, 9
	ldi r30,LOW(2*msg3) ; Load Z register low
    ldi r31,HIGH(2*msg3) ; Load Z register high
	rcall displayCString
	ret

Secondline:
	cbi PORTB, PB5 ; set RS to 0 for commands 
	ldi r17, 0x0C  ; upper nibble to change DDRAM address to 40 (second line)
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x00 ; lower nibble for second line
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	sbi PORTB, PB5 ; set RS back to 1 for characters
	ret

displayCString:
L20:
	lpm ; r0 <-- first byte
	swap r0 ; Upper nibble in place
	out PORTC,r0 ; Send upper nibble out
	rcall LCDStrobe ; Latch nibble
	rcall delay_ms ; Wait
	swap r0 ; Lower nibble in place
	out PORTC,r0 ; Send lower nibble out
	rcall LCDStrobe ; Latch nibble
	rcall delay_ms ; Wait
	adiw zh:zl,1 ; Increment Z pointer
	dec r24 ; Repeat until
	brne L20 ; all characters are out
	ret

LCDStrobe:
	sbi PORTB, PB3
	rcall delay_ms
	rcall delay_ms
	cbi PORTB, PB3
	ret

displayDC:
.dseg 
	dtxt: .BYTE 4 ;allocation for duty cycle == 100%
	twoDigit: .BYTE 3 ;allcoation for duty cycle < 100%
.cseg
	mov dd8u, value ; load value into dividend
	ldi dv8u, 2 ; divisor 
	rcall div8u ; divide value by 2 to get duty cycle 

	cpi dres8u, 100 ; see if duty cycle is at 100%
	breq onehundred

	ldi r29, 0x00 
	sts	twoDigit+2, r29	; load in terminating null byte

	; ones place
	ldi dv8u, 10 
	rcall div8u			
	ldi r29, 0x30
	add drem8u, r29
	sts twoDigit+1, drem8u
	
	; tens place 
	rcall div8u
	add drem8u, r29
	sts twoDigit, drem8u
	rjmp read

onehundred: ; if duty cyle is 100%
	ldi		r29, 0x00
	sts		dtxt+3, r29
	ldi		temp, 0x30
	sts		dtxt+2, temp
	sts		dtxt+1, temp
	ldi		temp, 0x31
	sts		dtxt, temp

readhundred: ;read dseg bytes
	ldi r30, LOW(dtxt)
	ldi r31, HIGH(dtxt)
	rjmp displayDString

read: ; read dseg bytes for twodigit
	ldi r30, LOW(twoDigit)
	ldi r31, HIGH(twoDigit)
	rjmp displayDString

displayDstring:
	ld r0,Z+
	tst r0 ; Reached end of message ?
	breq done_dsd ; Yes => quit
	swap r0 ; Upper nibble in place
	out PORTC,r0 ; Send upper nibble out
	rcall LCDStrobe ; Latch nibble 
	swap r0 ; Lower nibble in place
	out PORTC,r0 ; Send lower nibble out
	rcall LCDStrobe ; Latch nibble
	rjmp displayDString

done_dsd:
	ret

LCDinit:
	ldi r16, 0x28 ;all 1s in B
	out DDRB, r16

	ldi r16, 0xFF ;all 1s in C
	out DDRC, r16

	ldi r16, 0x65 ;100 ms
	rcall delay_mms

	ldi r17, 0x03 ;8 bit mode 
	out PORTC, r17
	rcall LCDStrobe
	ldi r16, 5 ; 
	rcall delay_mms;8 bit mode, DB3 and DB2 high
	out PORTC, r17
	rcall LCDStrobe;pulse enable to change mode
	ldi r16, 1 ; >200us
	rcall delay_mms;8 bit mode, DB3 and DB2 high
	out PORTC, r17
	rcall LCDStrobe;pulse enable to change mode
	ldi r16, 6 ; >200us
	rcall delay_mms
	

	ldi r17, 0x02 ; 4 bit mode
	out PORTC, r17
	nop
	rcall LCDStrobe
	ldi r16, 6
	rcall delay_mms

	; 4 bit 2 line 
	ldi r17, 0x02 
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x08
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	;set cursor
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x08
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	;clear display
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x01
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	;set cursor move to right
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ldi r17, 0x06
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	;turn on display 
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ldi r17, 0x0C
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ret	
div8u:	
	sub	drem8u,drem8u	;clear remainder and carry
	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_1		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_2		;else
d8u_1:	sec			;    set carry to be shifted into result

d8u_2:	
	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_3		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_4		;else
d8u_3:	sec			;    set carry to be shifted into result

d8u_4:	
	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_5		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_6		;else

d8u_5:	sec			;    set carry to be shifted into result

d8u_6:	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_7		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_8		;else

d8u_7:	sec			;    set carry to be shifted into result

d8u_8:	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_9		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_10		;else
d8u_9:	sec			;    set carry to be shifted into result

d8u_10:	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_11		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_12		;else
d8u_11:	sec			;    set carry to be shifted into result

d8u_12:	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_13		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_14		;else
d8u_13:	sec			;    set carry to be shifted into result

d8u_14:	rol	dd8u		;shift left dividend
	rol	drem8u		;shift dividend into remainder
	sub	drem8u,dv8u	;remainder = remainder - divisor
	brcc	d8u_15		;if result negative
	add	drem8u,dv8u	;    restore remainder
	clc			;    clear carry to be shifted into result
	rjmp	d8u_16		;else
d8u_15:	sec			;    set carry to be shifted into result

d8u_16:	rol	dd8u		;shift left dividend
	ret

delay_mms:
	ldi		temp, (1 << TOIE0)
	sts		TIMSK0, temp		; enable TOV interrupts 
	delayLoop:
		dec r16
		rcall delay_ms
		cpi r16, 0
		brne delayLoop
	ldi		temp, (0 << TOIE0)	; disable TOV interrupts
	sts		TIMSK0, temp
	ret

 delay_ms: 
	push	temp
	ldi		temp, 6
	out		TCNT0, temp

	ldi		temp, (1 << TOIE0)
	sts		TIMSK0, temp		; enable TOV interrupts 
	wait: 
		sbis	TIFR0, TOV0
		rjmp	wait
	
	ldi		temp, (1 << TOV0)
	out		TIFR0, temp		; Clear TOV0 / clear pending interrupts 
	ldi		temp, (0 << TOIE0)	; disable TOV interrupts
	sts		TIMSK0, temp
	pop		temp 
	ret 
