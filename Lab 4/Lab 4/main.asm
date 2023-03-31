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

.org 0x0002				; PCINT0
	rjmp INT0_vect


.org 0x0034

.def temp = r18
.def value = r20		; Current value of rpg, used to calc duty cycle
.def input = r22		; State of the rpg 	
.def fanBool = r19		; state of the fan 
.def curr = r17
.def update = r24
;rjmp RESET

RESET:
	cli
	ldi		temp, LOW(RAMEND)
	out		SPL, temp
	ldi		temp, HIGH(RAMEND)
	out		SPH, temp
	ldi		fanBool, 1			; fans initial state is off
	ldi		update, 0
;---------------------PIN CONFIGURATION-------------------------
	clr		r16							; reset r16
	ldi		r16, (1<<DDB3) | (1<<DDB5)	; set pins 3 and 5 as outputs for the LCD
	out		DDRB, r16
	cbi		DDRB, 0
	cbi		DDRB, 1 
	cbi		DDRB, 2
	sbi		DDRB, 4
	ldi		temp, (1<<PB2) | (1<<PB4)
	out		PORTB, temp					; enable pullup for pinb 2
	ldi		temp, (1<<PD2)
	out		PORTD, temp
	ldi		temp, (1<<PD3)
	out		DDRD, temp					; enable OCRB output 
	
;--------------------Setup pin interrupts------------------------	
	// PCINT0-1 - RPG interrupts
	// PCINT2	- PB  interrupt
	ldi		temp, (1<<INT0)
	out		EIMSK, temp
	ldi		temp, 0x02
	sts		EICRA, temp

;--------------- Initialize Timer/Counter for fast PWM mode --------------
	ldi		temp,  (1<<COM2B1) |(1<<WGM21) | (1<<WGM20)
	sts		TCCR2A, temp								; set to fast non-inverting PWM mode with OC2A as TOP

	ldi		temp,  (1 << WGM22) |(1 << CS20) 
	sts		TCCR2B, temp								; set the OC2RA as TOP and 1-prescaling

	ldi		temp, 200									; top value, this allows 0-199 steps in duty cycle. or 200 total steps 
	sts		OCR2A, temp			
			
	ldi		value, 30									; Set the starting duty cycle
	mov		temp, value
	sts		OCR2B, temp

	;ldi		temp, (1<<OCIE2A)| (1<<OCIE2B) | (1 << TOIE2)	; enable T/C2 interrupts 
	;sts		TIMSK2, temp
;--------------Enable T/C0 for delays-------------------------------------
	ldi		temp, (1<<CS01) | (1<<CS00)
	out		TCCR0B, temp	; Timer clock = system clock / 64
	ldi		temp, (1 << TOV0)
	out		TIFR0, temp		; CLear TOV0 / clear pending interrupts 
	;ldi		temp, (1 << TOIE0)
	;sts		TIMSK0, temp



sei
main: 
	nop
	cpi	update, 1
	breq ToggleFan 
	rjmp main

INT0_vect: 
	ldi		temp, SREG		; save state of SREG
	push	temp
	cli 

	ldi		update, 0x01

	ldi		temp, 0x01
	eor		fanBool, temp

	rjmp	intDONE			 

ToggleFan:
	cli
	ldi update, 0
	cpi fanBool, 1 
	breq turnFanOn
	cpi fanbool, 0
	breq turnFanOff
	sei
	jmp main

turnFanOff:
	cbi		PORTB, PB4 
	ldi		temp, 0
	
	sts		OCR2B, temp		
	clr		temp
	ldi		temp, 0x00		; turn RPG interrupts off. Keep button interrupts
	sts		PCMSK0, temp
	sei
	rjmp	main

turnFanOn: 
	sbi		PORTB, PB4

	ldi		temp, 0x03		; turn RPG control back on
	sts		PCMSK0, temp


	cpi		value, 50		; check if DC > 25%
	rcall	rampUp
	sei
	rjmp	main

rampUp: 
	ldi		temp, 200		; ramp fan up to 25% DC 
	sts		OCR2B, temp		
	nop
	nop
	nop
	sts		OCR2B, value		; bring fan speed back to previous state	
	
	sei
	ret

intDONE:
	pop temp
	out SREG, temp	; return the state of the SREG
	sei 
	reti