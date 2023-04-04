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
;---------------------PIN CONFIGURATION-------------------------
	clr		r16							; reset r16
	ldi		r16, (1<<DDB3) | (1<<DDB5)	; set pins 3 and 5 as outputs for the LCD
	out		DDRB, r16
	cbi		DDRB, 0
	cbi		DDRB, 1 
	cbi		DDRB, 2
	sbi		DDRB, 4
	ldi		temp, (1<<PB2) | (1<<PB4) | (1<<PB3)
	out		PORTB, temp					; enable pullup for pinb 2
	ldi		temp, (1<<PD2)
	out		PORTD, temp
	ldi		temp, (1<<PD3)
	out		DDRD, temp					; enable OCRB output 
	
;--------------------Setup pin interrupts------------------------	
	// PCINT0-1 - RPG interrupts
	// INT0	- PB  interrupt
	ldi		temp, 0x02		; enable INT0 interrupts
	sts		EICRA, temp

	ldi		temp, (1<<INT0)	; enables int0 flag. 
	out		EIMSK, temp


	ldi		temp, (1<<PCIE0)
	sts		PCICR, temp

	ldi		temp, (1<<PCINT0) | (1<<PCINT1)
	sts		PCMSK0, temp

;--------------- Initialize Timer/Counter for fast PWM mode --------------
	ldi		temp,  (1<<COM2B1) |(1<<WGM21) | (1<<WGM20)
	sts		TCCR2A, temp								; set to fast non-inverting PWM mode with OC2A as TOP

	ldi		temp,  (1 << WGM22) |(1 << CS20) 
	sts		TCCR2B, temp								; set the OC2RA as TOP and 1-prescaling

	ldi		temp, 200									; top value, this allows 0-199 steps in duty cycle. or 200 total steps 
	sts		OCR2A, temp			
			
	ldi		value, 160									; Set the starting duty cycle
	mov		temp, value
	sts		OCR2B, temp

;--------------Enable T/C0 for delays-------------------------------------
	ldi		temp, (1<<CS01) | (1<<CS00)
	out		TCCR0B, temp	; Timer clock = system clock / 64

rcall LCDinit
rcall updateDC
rcall fanON

sei
main: 
	sbrc	update, 0
	rjmp	ToggleFan
	sbrc	update, 1
	rjmp	incrementDC
	sbrc	update, 2
	rjmp	decrementDC
	
	rjmp	main
INT0_vect: 
	ldi		temp, SREG		; save state of SREG
	push	temp
	cli 
	ldi		update, 0x01

	ldi		temp, 0x01
	eor		fanBool, temp

	rjmp	intDONE			 
TOV0_INT:
	ldi		temp, SREG		; save state of SREG
	push	temp
	cli 
	ldi		temp, (1 << TOV0)
	out		TIFR0, temp		; Clear TOV0 / clear pending interrupts 
	rjmp	intDONE		
		 
PCINT0_INT:
	ldi		temp, SREG		; save state of SREG
	push	temp
	cli
	in		input, PINB
	andi	input, 0x03		; mask out PINA and PINB

	inc		rpgInterruptCount
	cpi		rpgInterruptCount, 1
	breq	firstTime

	cpi		rpgInterruptCount, 4 
	breq	DONE
	rjmp	intDONE

DONE: 
	;mov		update, tempUpdate
	clr		rpgInterruptCount
	rjmp	intDONE

firstTime:
	cpi		input, 0x01
	breq	rpgCW
	cpi		input, 0x02
	breq	rpgCCW

	rjmp	intDONE

rpgCW: 
	ldi		update, 0x02
	rjmp	intDONE
rpgCCW: 
	ldi		update, 0x04
	rjmp	intDONE

incrementDC:
	cli
	clr		update

	cpi		value, 200
	breq	incDone

	ldi		temp, 2
	add		value, temp
incDone:
	sts		OCR2B, value		
	// update DC 
	cli
	rcall	updateDC
	rcall	fanON
	sei
	rjmp	main

decrementDC:
	cli
	clr		update

	cpi		value, 0
	breq	decDone

	ldi		temp, 2
	sub		value, temp
decDone: 
	sts		OCR2B, value	
		
	// update DC
	cli 
	rcall	updateDC
	rcall	fanON
	sei
	rjmp	main

		  
ToggleFan:
	clr		update
	cpi fanBool, 1 
	breq turnFanOn
	cpi fanbool, 0
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

intDONE:
	pop temp
	out SREG, temp	; return the state of the SREG
	sei 
	reti

updateDC:
	cbi PORTB, PB5
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x01
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x02
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	sbi PORTB, PB5
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
	;rcall Firstline
	ret

fanOFF:
	rcall SecondLine
	ldi r24, 9
	ldi r30,LOW(2*msg3) ; Load Z register low
    ldi r31,HIGH(2*msg3) ; Load Z register high
	rcall displayCString
	;rcall Firstline
	ret

Firstline:
	cbi PORTB, PB5
	ldi r17, 0x08
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	ret

Secondline:
	cbi PORTB, PB5
	ldi r17, 0x0C
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	sbi PORTB, PB5
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
	dtxt: .BYTE 4 ;allocation
	twoDigit: .BYTE 3
.cseg
	mov dd8u, value
	ldi dv8u, 2
	rcall div8u

	cpi dres8u, 100
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

onehundred:
	ldi		r29, 0x00
	sts		dtxt+3, r29
	ldi		temp, 0x30
	sts		dtxt+2, temp
	sts		dtxt+1, temp
	ldi		temp, 0x31
	sts		dtxt, temp

readhundred:
	ldi r30, LOW(dtxt)
	ldi r31, HIGH(dtxt)
	rjmp displayDString

read:
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