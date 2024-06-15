/*
 * ATTINY84A_SIO_SPI.c
 *
 * Created: 04/06/2024 17:10:37
 * Author : Arduino
 */ 

#define F_CPU 8000000UL		// 8MHz system clock

#include <avr/io.h>
#include <util/delay.h>

#define SPI_CLK		PORTA0	// OUT : CLOCK to the SPI peripheral(s)
#define SIO_CTS		PORTA1	// OUT : CTS signal to Z80 SIO CTS
#define SIO_SYNC	PORTA2	// OUT : SYNC signal to the Z80 SIO
#define TX_REQ		PINA3	// IN  : Tx byte request pulse (RTS) (TIMER/COUNTER #0 clock source)
// Save PA4 as it's TIMER/COUNTER #1 clock source
#define SIO_CLK		PORTA5	// OUT : CLOCK to the Z80 SIO
// Save PA6 as it's TIMER/COUNTER #1 Compare/Match A output
#define SIO_DTR		PINA7	// IN  : SPI Message Transfer signal from Z80 SIO DTR

#define SIO_DTR_HIGH	(1<<SIO_DTR)
#define SIO_DTR_LOW		0x00

void preTransmission( void );
void postTransmission( void );
void sio8Clocks( void );

const uint16_t spiClockPulseWidth = 50;

uint8_t  prevDTRState = 0;
uint8_t  currDTRState = 0;
uint16_t prevTxCounter = 0;

int main(void)
{
	// SPI Clock + SIO Clock + SIO Sync + SIO CTS are outputs
	DDRA = (1<<SIO_CLK) | (1<<SPI_CLK) | (1<<SIO_SYNC) | (1<<SIO_CTS);

	// SIO_SYNC & SIO_CTS start out HIGH
	PORTA = (1<<SIO_SYNC) | (1<<SIO_CTS);

	// configure Timer/Counter #0 as an up-counter counting falling edge of pulses on the T0 pin
	TIMSK0 = 0;		// no interrupts from Timer/Counter #0
	TCCR0A = 0;     // normal operation
	TCCR0B = 0x06;  // clock on falling edge of pulse on T0 pin
	TCNT0  = 0;     // reset the pulse counter

	prevDTRState = PINA & (1<<SIO_DTR);
	currDTRState = prevDTRState;
    	
    // FOREVER loop
    while (1) 
    {
		// read the state of the SPI transfer request control signal from the SIO
		currDTRState = PINA & (1<<SIO_DTR);
		
		// have we detected the beginning or end of a transmission?
		if (( prevDTRState == SIO_DTR_HIGH ) && ( currDTRState == SIO_DTR_LOW )) {
			// transfer request signal has just gone LOW - i.e. start of a message
			prevDTRState = currDTRState;
			preTransmission();
		}				
		else if ( TCNT0 !=  prevTxCounter ) {
			// generate 8 clock pulses for the SIO & SPI device
			sio8Clocks();
			prevTxCounter++;
		}
		else if (( prevDTRState == SIO_DTR_LOW ) && ( currDTRState == SIO_DTR_HIGH )) {
			// transfer request signal has just gone HIGH - i.e. end of a message
			postTransmission();
			prevDTRState = currDTRState;
		}
	}
}

// ========================================================================
// Called when SPI Message Transfer signal (DTR) goes LOW
// Sends out 2 complete clock cycles to the SIO, then sets CTS low.
// Assumes the SIO_CLK pin is LOW on entry.
// Assumes the SIO_CTS pin is HIGH on entry.
// ========================================================================
void preTransmission( void ) {

	PINA = (1<<SIO_CLK);	// toggle HIGH
	_delay_us( spiClockPulseWidth );
	PINA = (1<<SIO_CLK);	// toggle LOW
	_delay_us( spiClockPulseWidth );
	PINA = (1<<SIO_CLK);	// toggle HIGH
	_delay_us( spiClockPulseWidth );
	PINA = (1<<SIO_CLK);	// toggle LOW
	_delay_us( spiClockPulseWidth );

	PINA = (1<<SIO_CTS);	// toggle LOW
}

// ========================================================================
// Called when SPI Message Transfer signal (DTR) goes HIGH
// Generates additional clock pulses for the SIO to cause the SIO
// Rx hardware to release the final bytes.
// ========================================================================
void postTransmission( void ) {
	for (uint8_t i=0; i<16; i++) {
		PINA = (1<<SIO_CLK);	// toggle HIGH
		_delay_us( spiClockPulseWidth );
		PINA = (1<<SIO_CLK);	// toggle LOW
		_delay_us( spiClockPulseWidth );
	}

	// set SIO_SYNC HIGH & SIO_CTS HIGH
	PORTA = PORTA | (1<<SIO_SYNC) | (1<<SIO_CTS);

	// reset the Tx count back to zero
	prevTxCounter = 0;
	TCNT0  = 0;     // reset the pulse counter
}

// ========================================================================
// Generates 8 clock pulses to clock out a byte from the SIO
// and 8 clock pulses for the SPI peripheral.
// Assumes the SIO_CLK & SPI_CLK pins are LOW on entry.
// ========================================================================
void sio8Clocks() {

	
	for ( uint8_t p=0; p<8; p++) {
		// toggle SIO_SYNC HIGH & SIO_CTS HIGH
		PINA = (1<<SIO_CLK) | (1<<SPI_CLK);
		_delay_us( spiClockPulseWidth/2 );

		// set SIO_SYNC LOW
		PORTA = PORTA & ~(1<<SIO_SYNC );
		_delay_us( spiClockPulseWidth/2 );

		// toggle SIO_SYNC HIGH & SIO_CTS LOW
		PINA = (1<<SIO_CLK) | (1<<SPI_CLK);
		_delay_us( spiClockPulseWidth );
	}
}
