;
; Lab 4.asm
;
; Created: 3/28/2023 12:05:42 PM
; Authors : James Ostrowski and Kai Lindholm 
;

.include "m328Pdef.inc"
.cseg
.org 0x00 ; PC points here after reset

.def temp = r18
.def value = r20		; Current value of rpg, used to calc duty cycle
.def input = r22		; State of the rpg 
.def prevInput = r21	;		

msg1: .db "DC = ", 0x00
msg2: .db "Fan = ", 0x00, 0
msg3: .db " % ", 0x00

rjmp start

start:
	ldi		temp, LOW(RAMEND)
	out		SPL, temp
	ldi		temp, HIGH(RAMEND)
	out		SPH, temp
;--------------- Initialize Timer/Counter for fast PWM mode --------------
	ldi temp, (1<<OCIE2A)| (1<<OCIE2B) | (1 << TOIE2)	; enable TC2 interrupts 
	sts TIMSK2, temp

	ldi temp,  (1<<COM2B1) |(1<<WGM21) | (1<<WGM20)
	sts TCCR2A, temp								; set to fast non-inverting PWM mode with OC2A as TOP

	ldi temp,  (1 << WGM22) |(1 << CS20) 
	sts TCCR2B, temp								; set the OC2RA as TOP and 1-prescaling

	ldi temp, 200									; top value, this allows 0-199 steps in duty cycle. or 200 total steps 
	sts OCR2A, temp			
			
	ldi value, 0									; Set the starting duty cycle to 0
	mov temp, value
	sts OCR2B, temp
	
	ldi temp, (1<<PD3)
	out DDRD, temp			;	 enable OCRB output 

	ldi		temp, (1<<CS01) | (1<<CS00)
	out		TCCR0B, temp	; Timer clock = system clock / 64
	ldi		temp, 1 << TOV0
	out		TIFR0, temp		; CLear TOV0 / clear pending interrupts 
	ldi		temp, 1 << TOIE0
	sts		TIMSK0, temp
	
		
    rcall LCDinit
	sbi PORTB, PB5
	ldi r24, 5
	ldi r30,LOW(2*msg1) ; Load Z register low
    ldi r31,HIGH(2*msg1) ; Load Z register high
    rcall displayCString
	ldi r24, 3
	ldi r30,LOW(2*msg3) ; Load Z register low
    ldi r31,HIGH(2*msg3) ; Load Z register high
    rcall displayCString
	rcall Secondline
	ldi r24, 6
	ldi r30,LOW(2*msg2) ; Load Z register low
    ldi r31,HIGH(2*msg2) ; Load Z register high
	rcall displayCString

main:
	in		input, PINB
	andi	input, 0x02
	cpi		input, 0x02
	in		input, PINB			; load in current state of RPG
	andi	input, 0x01			; extract new input values 
	cp		prevInput, input	 
	brne	direction			; if the current current state is not the same, determine the direction
	rtn: 
		mov		prevInput, input	; store current value of input, in previnput for next iteration 
		in		input, pinb			
		andi 	input, 0x03	
		cpi		input, 0x03			; check if the RPG is back at a non moving state
		brne	rtn					; if not, stay in rtn until true 
		rjmp	main	

direction: 
	in		temp, PINB
	andi	temp, 0x02
	lsr		temp
	cp		input, temp		; compares previous pin A state to current pin B state. 
	breq	increment 		; if the states are equal, RPG is moving CW; Increment
	rjmp	decrement 		; else states are not equal, RPG is moving CCW; Decrement

increment: 
	cpi		value, 200			; if the value is 16, we have reached the max value that can be displayed do nothing
	breq	rtn					
	ldi		temp, 10
	add		value, temp
	sts		OCR2B, value
	
	mov		prevInput, temp		; store current input in prev input for next iteration 
	rjmp	rtn

decrement:
	cpi		value, 0x00
	breq	rtn					; if value has reached 0, do not allow shift reg to change states
	; ----------------
	ldi		temp, 10
	sub		value, temp
	sts		OCR2B, value

	mov		prevInput, temp		; store current input in prev input for next iteration 
	rjmp	rtn

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
delay_mms:
	loop:
		rcall delay_ms
		dec r16
		brne loop
	ret


delay_ms:
		push	temp				
		ldi		temp, 6
		out		TCNT0, temp
		clr		temp
		wait2: 
			in		temp, TCNT0
			cpi		temp, 0x00		; has the overflow bit been set
			brne	wait2			; if not wait. 

		pop		temp
	    ret
	
