# SC104-SIO2-does-SPI
 
I've been scoping out the goundwork for a possible RetroDuino-Z80 board along the lines of my RetroDuino-8085 and got intrigued by the possibility of using a Z80 SIO/2 chip as an SPI device.
 
My first thought was - no way, why would an SIO/2 know how to handle SPI messages! But then I started reading through the Zilog SIO Technical Manual and a cunning plan began to form.

Long story short, yes you can convince a Zilog SIO/2 to handle SPI messages. It just needs a little bit of assistance.

The key is to configure the SIO/2 for synchronous mode with an external sync. Note that I'm using an SIO/2 device and only channel A can do this. The limitation is due to the various bonding options for the SIO/0, SIO/1 and SIO/2 chips and what signals are not present. With the SIO/2, there is no SYNC_B pin.

Below is what I've achieved so far:

# SPI Transmit

This was easily the simplest to achieve as all I needed to do was provide a suitable clock signal into the TxCA pin. However, the clock should only be present when there is a byte to transmit. If the clock is applied continuously and there is no data in the transmit buffer, then the SIO will clock out the transmit sync character that has been programmed into WR6 (Write Register 6).

I discovered that if I were to:
1. Write the byte to the transmit buffer
2. Enable the transmitter (WR5 bit 3)
3. Apply a series of clock pulses to the TxCA

Then the SIO/2 would clock out the byte on TxDA. The SIO Technical Manual says that TxD changes on the falling edge of TxC - just like SPI Mode 0.

What I did notice was that the data came out LSB first and that the data started appearing on the falling edge of the second clock pulse.

# SPI Receive

The SIO Technical Manual says that receive data is sampled on the rising edge of RxC - just like SPI Mode 0.

Receiving data was more difficult. I had to set SYNC_A low at the right time. I hit a further stumbling block when I got 3 random bytes back at the start of the received message and couldn't seem to receive the whole message.

After a bit of playing around, I discovered that the SIO/2 in synchronous mode doesn't quite work like an AVR SPI interface. There is the exchange of bytes just like SPI, but the SIO/2 seems to have a 3 byte receive FIFO. After transmitting each byte, I checked RR0 (Read Register 0) bit 0 to see if a byte was available. It appears the byte is only available once it had passed though the FIFO. Once I figured that out, I could then receive the first few bytes that the remote SPI device was sending.

It took a little bit more experimenting to get the complete message out as I needed to apply additional clocks to the RxC pin in order to push the final few bytes out of the receive FIFO.

# The Hardware

I have a great little retro system based around several boards designed by Steve Cousins at [Small Computer Central](https://smallcomputercentral.com/). My setup has:
- [SC108](https://smallcomputercentral.com/sc108-z80-processor-rc2014/) Z80 Processor Module
- [SC110](https://smallcomputercentral.com/sc110-z80-serial-rc2014-3/) Serial and Timer Module
- [SC129](https://smallcomputercentral.com/sc129-digital-i-o-rc2014/) Digital I/O Module
- SC145 CompactFlash Module
- [SC112](https://smallcomputercentral.com/sc112-modular-backplane-rc2014/) 6 Slot Modular Backplane

In order to investigate further the possibility of using an SIO/2, I have an [SC104](https://smallcomputercentral.com/sc104-z80-sio-2-module-rc2014/) SIO/2 Module that I've modified to support my experiments.


 
