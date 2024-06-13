// =========================================================================
// Arduino UNO Pulse & Data Generator for the RC2014 SC104 SIO/2 module
// https://smallcomputercentral.com/sc104-z80-sio-2-module-rc2014/
// =========================================================================

#define spiClk  PORTB4  // PB4: OUT : CLOCK to the SPI peripheral(s)
#define sioClk  PORTB3  // PB3: OUT : CLOCK to the Z80 SIO
#define sioSync PORTB2  // PB2: OUT : SYNC signal to the Z80 SIO
#define sioDTR  PINB0   // PB0: IN  : XFER REQUEST signal from Z80 SIO (DTR signal)

#define sioCTS  PORTD7  // PD7: OUT : CTS signal to Z80 SIO CTS

// Tx byte request pulse (RTS) to pin PD5 aka Timer/Counter #1 ext clock input pin
#define sioRTS  PIND5   // PD5: IN  : TX REQUEST pulse from Z80 SIO (RTS signal)

#define SIO_DTR_HIGH  (1<<sioDTR)
#define SIO_DTR_LOW   0x00

const uint16_t spiClockPulseWidth = 8;    // about 8us high & 8us low

uint8_t prevDTRState = 0;
uint8_t currDTRState = 0;
uint16_t prevTxCounter = 0;

void setup() {
  Serial.begin( 115200 );
  Serial.println(F("\n\n============================================================="));
  Serial.println(F("Arduino UNO Pulse & Data Generator for the Z80 KIO-SIO module"));
  Serial.println(F("============================================================="));

  Serial.println(F("\nPin definitions are:\n"));
  Serial.println(F("PB0 : INPUT  : XFER REQUEST signal from Z80 SIO (DTR signal)"));
  Serial.println(F("PB2 : OUTPUT : SYNC signal to Z80 SIO"));  
  Serial.println(F("PB3 : OUTPUT : CLOCK signal to Z80 SIO TxC & RxC pins"));
  Serial.println(F("PB4 : OUTPUT : CLOCK signal to SPI peripheral(s)\n"));
  
  Serial.println(F("PD5 : INPUT  : TX REQUEST pulse from Z80 SIO (RTS signal)"));
  Serial.println(F("PD7 : OUTPUT : CTS signal to Z80 KIO CTS pin\n\n"));

  // configure Timer/Counter #1 as an up-counter counting pulses on the T1 pin
  TIMSK1 = 0;     // no interrupts from Timer/Counter #1
  TCCR1A = 0;     // normal operation
  TCCR1B = 0x06;  // clock on falling edge of pulse on T1 pin (PD5)
  TCNT1  = 0;     // reset the pulse counter

  // set spiClk, sioClk, sioSync & sioCTS pins as outputs
  DDRB = DDRB | (1<<spiClk) | (1<<sioClk) | (1<<sioSync);
  DDRD = DDRD | (1<<sioCTS);

  // sioDTR should already be an input but make sure
  DDRB = DDRB & (~(1<<sioDTR));  
 
  PORTB = PORTB & (~(1<<spiClk));   // SPI clock pin LOW
  PORTB = PORTB & (~(1<<sioClk));   // SIO clock pin LOW
  PORTB = PORTB | (1<<sioSync);     // SIO sync  pin HIGH
  PORTD = PORTD | (1<<sioCTS);      // SIO CTS   pin HIGH

  prevDTRState = PINB & (1<<sioDTR);
  currDTRState = prevDTRState;
}

// ========================================================================
// Called when SPI Message Transfer signal (DTR) goes LOW
// Sends out 2 complete clock cycles to the SIO, then sets CTS low.
// Assumes the SIO_CLK pin is LOW on entry.
// Assumes the SIO_CTS pin is HIGH on entry.
// ========================================================================
void preTransmission( void ) {

  PINB = (1<<sioClk);     // set HIGH
  delayMicroseconds( spiClockPulseWidth );
  PINB = (1<<sioClk);     // set LOW
  delayMicroseconds( spiClockPulseWidth );
  PINB = (1<<sioClk);     // set HIGH
  delayMicroseconds( spiClockPulseWidth );
  PINB = (1<<sioClk);     // set LOW
  delayMicroseconds( spiClockPulseWidth );

  PORTD = PORTD & (~(1<<sioCTS));      // SIO CTS pin LOW
}

// ========================================================================
// Called when SPI Message Transfer signal (DTR) goes HIGH
// Generates additional clock pulses for the SIO to cause the SIO
// Rx hardware to release the final bytes.
// Assumes the SIO_CLK pin is LOW on entry.
// ========================================================================
void postTransmission( void ) {
  for (uint8_t i=0; i<16; i++) {
    PINB = (1<<sioClk);     // set HIGH
    delayMicroseconds( spiClockPulseWidth );
    PINB = (1<<sioClk);     // set LOW
    delayMicroseconds( spiClockPulseWidth );
  }
  PORTB = PORTB | (1<<sioSync);     // SIO sync  pin HIGH
  PORTD = PORTD | (1<<sioCTS);      // SIO CTS   pin HIGH

  // reset the tx count back to zero
  prevTxCounter = 0;
  TCNT1  = 0;     // reset the pulse counter
}

void loop() {

  // read the state of the xfer request control signal from the SIO
  currDTRState = PINB & (1<<sioDTR);

  // have we detected the beginning or end of a transmission?
  if (( prevDTRState == SIO_DTR_HIGH ) && ( currDTRState == SIO_DTR_LOW )) {
    // transfer request signal has just gone LOW - i.e. start of a message
    Serial.print('S');
    prevDTRState = currDTRState;
    preTransmission();
  }
  else if ( TCNT1 !=  prevTxCounter ) {
    // generate 8 clock pulses for the SIO & SPI device
    sio8Clocks();
    prevTxCounter++;
    Serial.print('.');
  }
  else if (( prevDTRState == SIO_DTR_LOW ) && ( currDTRState == SIO_DTR_HIGH )) {
    // transfer request signal has just gone HIGH - i.e. end of a message
    postTransmission();
    prevDTRState = currDTRState;
    Serial.println('P');
    Serial.println( TCNT1 );
  }
}

// ========================================================================
// Generates 8 clock pulses to clock out a byte from the SIO
// Also generates 8 clock pulses for the SPI peripheral.
// Assumes the SIO_CLK & SPI_CLK pins are LOW on entry.
// ========================================================================
void sio8Clocks() {

  for ( uint8_t p=0; p<8; p++) {
    PINB = (1<<sioClk) | (1<<spiClk);     // set SIO CLK & SPI CLK HIGH

    delayMicroseconds( spiClockPulseWidth );

    PINB = (1<<sioClk) | (1<<spiClk);     // set SIO CLK & SPI CLK LOW
    delayMicroseconds( spiClockPulseWidth/2 );
    PORTB = PORTB & (~(1<<sioSync));      // set SIO SYNC LOW
    delayMicroseconds( spiClockPulseWidth/2 );
  }
}