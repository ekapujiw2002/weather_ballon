/*
* kombat2014_1.c
*
* Created: 3/4/2014 5:14:43 AM
*  Author: EX4
* all variable is big endian (lsb at lower memory address)
*/

//lib
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/crc16.h>
#include <util/delay.h>
#include <avr/wdt.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//device lib
#include "bmp085.h"
#include "dht.h"
#include "uart.h"
#include "i2c_gps.h"
#include "adc.h"

//setting
#define USART_BAUD_RATE			1200	//baudrate in bps
#define MAX_CMD_BUFFER_SIZE		16		//buffer size for command from master in byte
#define MAX_REPLY_BUFFER_SIZE	40		//buffer size for reply in byte
#define MAX_CNT_CMD_TOUT		50000	//usart read timeout in us

#define DEVICE_ID			1			//this payload id
#define MASTER_ID			0			//master id

/*
workmode:
0 = test
1 = real
*/
#define WORK_MODE			1

//cmd list
#define CMD_GET_DATA		1			//get the data
#define CMD_STATUS			0xff		//status reply

//reply length
#define LENGTH_REPLY		27

//status detil
#define STATUS_CRC_ERROR	0		//command error crc
#define STATUS_CMD_UNKNOWN	1		//command is unknown

//adc scaling
#define PWR_SCALE	(1000/1024)

/*
calculate crc16 modbus style
*/
uint16_t CalcCRC(uint8_t *buffer, uint8_t data_len)
{
	uint16_t crcx = 0xffff, i;
	for (i=0;i<data_len;i++)
	{
		crcx = _crc16_update(crcx, buffer[i]);
	}
	return crcx;
}

/*
get dht22 humidity
scaling = 100
*/
uint16_t GetHumidity()
{
	float dht_temp, dht_humidity;
	
	if(dht_gettemperaturehumidity(&dht_temp, &dht_humidity) != -1)
	{
		return (dht_humidity*100);
	}
	else
	{
		return 0;
	}
}

/*
get bmp180 pressure, temp, and altitude
*/
void GetBMPData(int32_t *pressure, int16_t *temperature, int32_t *altitude)
{
	*temperature = bmp085_gettemperature() * 100;
	*pressure = bmp085_getpressure();
	*altitude = bmp085_getaltitude() * 100;
}

/*
get gps data
*/
void GetGPSData(uint8_t *status, int32_t *latpos, int32_t *lonpos, uint16_t *gndspeed, uint32_t *timestamp)
{
	uint16_t gps_altitude;
	//read status
	*status = i2c_gps_read_status();
	//read lat lon
	i2c_gps_read_lat_lon(latpos,lonpos);
	//read speed altitude
	i2c_gps_read_speed_altitude(gndspeed, &gps_altitude);
	//read time
	i2c_gps_read_time(timestamp);
}

/*
get data from usart
*/
uint8_t GetCommandFromUSART(uint8_t *aDataBuffer,uint8_t buffer_length, uint32_t max_uart_tout_cnt)
{
	uint8_t id_buff;
	uint32_t uart_tout_cnt;
	uint16_t uart_data;
	
	id_buff = 0;
	uart_tout_cnt = 0;
	while ((id_buff<(buffer_length-1)) && (uart_tout_cnt<max_uart_tout_cnt))
	{
		uart_tout_cnt = 0;
		while(((uart_data = uart_getc()) == UART_NO_DATA) && (uart_tout_cnt<max_uart_tout_cnt)) //wait data arrive or tout
		{
			uart_tout_cnt++;
			_delay_us(1);
		}
		
		if (uart_tout_cnt>=max_uart_tout_cnt)
		{
			break;
		}
		else
		{
			aDataBuffer[id_buff] = uart_data;
			id_buff++;
		}
	}
	
	return id_buff;
}

/*
parse cmd
cmd is big endian
cmd detil :
id target-command code-data length-data-crc
1			1			1			n
*/
uint8_t ParseCommand(uint8_t *aCommand, uint8_t aDevID)
{
	uint8_t resx = 0;
	uint16_t crc_in, crc_calcx;
	
	//1. cek id
	if (aCommand[0]==aDevID)
	{
		//cek crc
		crc_in = (aCommand[aCommand[2]+3]<<8) + aCommand[aCommand[2]+4];
		crc_calcx = CalcCRC(&aCommand[0],aCommand[2]+3);
		if (crc_in==crc_calcx)
		{
			resx = aCommand[1];
		}
		else
		{
			resx = 0;
		}
	}
	else
	{
		resx = 0;
	}
	return resx;
}

/*
print a buffer
*/
void uart_send_buffer(uint8_t *abuffer, uint8_t asize)
{
	uint8_t i;
	for (i=0;i<asize;i++)
	{
		uart_putc(abuffer[i]);
	}
}

/*
send modbus reply
*/
void uart_send_reply(uint8_t idTarget, uint8_t aCommand, uint8_t dataLength, uint8_t *dataPayload)
{
	uint8_t buff[dataLength+8];
	uint8_t i;
	uint16_t crcx;
	
	i=0;
	buff[i++] = idTarget;
	buff[i++] = aCommand;
	buff[i++] = dataLength;
	if(dataLength!=0)
	memcpy(&buff[i],dataPayload, dataLength);
	i+=dataLength;
	crcx = CalcCRC(&buff[0],i);
	memcpy(&buff[i],&crcx, 2);
	i+=2;
	uart_send_buffer(&buff[0], i);
}

/*
send the payload data
*/
void SendDataPayload(uint8_t aCommand, uint8_t agps_status, int32_t agps_lat, int32_t agps_lon, uint32_t agps_timestamp, uint16_t agps_speed, int32_t abmp_pressure, int32_t abmp_altitude, int16_t abmp_temperature,uint16_t adht_humidity, uint16_t pwr_lvl)
{
	uint8_t buffer_reply[MAX_REPLY_BUFFER_SIZE], idBufferReply, i;
	uint16_t crc_calc;
	
	//format the data
	idBufferReply = 0;
	//master id
	buffer_reply[idBufferReply++] = MASTER_ID;
	//cmd set
	buffer_reply[idBufferReply++] = aCommand;
	//payload data length
	buffer_reply[idBufferReply++] = 0; //init = 0

	//gps data
	//status
	buffer_reply[idBufferReply++] = agps_status;
	//lat
	memcpy(&buffer_reply[idBufferReply], &agps_lat, sizeof(int32_t));
	idBufferReply+=sizeof(int32_t);
	//lon
	memcpy(&buffer_reply[idBufferReply], &agps_lon, sizeof(int32_t));
	idBufferReply+=sizeof(int32_t);
	//altitude
	//memcpy(&buffer_reply[idBufferReply], &gps_altitude, sizeof(uint16_t));
	//idBufferReply+=sizeof(uint16_t);
	//timestamp
	memcpy(&buffer_reply[idBufferReply], &agps_timestamp, sizeof(uint32_t));
	idBufferReply+=sizeof(uint32_t);
	//speed
	memcpy(&buffer_reply[idBufferReply], &agps_speed, sizeof(uint16_t));
	idBufferReply+=sizeof(uint16_t);

	//bmp data
	//pressure
	memcpy(&buffer_reply[idBufferReply], &abmp_pressure, sizeof(int32_t));
	idBufferReply+=sizeof(int32_t);
	//temperature
	memcpy(&buffer_reply[idBufferReply], &abmp_temperature, sizeof(int16_t));
	idBufferReply+=sizeof(int16_t);
	//altitude
	memcpy(&buffer_reply[idBufferReply], &abmp_altitude, sizeof(int32_t));
	idBufferReply+=sizeof(int32_t);

	//dht data
	//humidity
	memcpy(&buffer_reply[idBufferReply], &adht_humidity, sizeof(uint16_t));
	idBufferReply+=sizeof(uint16_t);
	
	//power level
	memcpy(&buffer_reply[idBufferReply], &pwr_lvl, sizeof(uint16_t));
	idBufferReply+=sizeof(uint16_t);

	//update data field length
	buffer_reply[2] = idBufferReply-3;

	//crc calc
	crc_calc = CalcCRC(&buffer_reply[0], idBufferReply);
	memcpy(&buffer_reply[idBufferReply], &crc_calc, sizeof(uint16_t));
	idBufferReply+=sizeof(uint16_t);

	//send data byte by byte
	for (i=0;i<idBufferReply;i++)
	{
		uart_putc(buffer_reply[i]);
	}
}

/*
cek level psu
out = 0-1000
scaling = 10
*/
uint16_t GetPowerSupplyLevel()
{
	uint16_t adcx = ADC_ReadData(ADC_CH0);
	if (adcx>1000)
	{
		adcx = 1000;
	}
	return adcx;
}


/*
main program
*/
int main(void)
{
	//var
	uint8_t uart_cmd[MAX_CMD_BUFFER_SIZE], cnt_buff;
	//uint8_t buffer_reply[MAX_REPLY_BUFFER_SIZE], idBufferReply;
	
	//data sensor
	int32_t bmp_pressure=0,  bmp_altitude = 0;
	int16_t bmp_temperature=0;
	uint16_t dht_humidity=0;
	
	//data gps
	uint8_t gps_status;
	int32_t	gps_lat, gps_lon;
	uint16_t gps_altitude, gps_speed;
	uint32_t gps_time_ms;
	
	//pwr lvl
	uint16_t pwr_level;
	
	//crc calc
	//uint16_t crc_calc;
	
	//util var
	//uint8_t i;
	
	//reinit watchdog
	wdt_enable(WDTO_2S);	//2seconds timeout

	//init uart
	uart_init( UART_BAUD_SELECT(USART_BAUD_RATE,F_CPU) );
	
	//init adc
	ADC_Init(ADC_VREF_INTERNAL,ADC_DATA_10BIT,ADC_PSC128);
	
	//init i2c
	i2c_init();

	//init bmp085
	bmp085_init();
	
	//isr
	sei();
	
	while(1)
	{
		//reset the watchdog
		wdt_reset();
		
		//get the command with timeout
		if ((cnt_buff = GetCommandFromUSART(&uart_cmd[0],sizeof(uart_cmd), MAX_CNT_CMD_TOUT)) != 0)
		{
			//get command validity
			cnt_buff = ParseCommand(uart_cmd, DEVICE_ID);
			
			//cek data
			//uart_send_buffer(uart_cmd,5);
			//uart_putc(cnt_buff);
			
			switch(cnt_buff)
			{
				case CMD_GET_DATA:
				//get all data from sensor
				//get gps data
				#if WORK_MODE==0	//test mode
				gps_status = 1;
				gps_lat = random();
				gps_lon = random();
				gps_time_ms = (uint32_t) random();
				gps_speed = (uint16_t) random();
				#else //real mode
				GetGPSData(&gps_status,&gps_lat,&gps_lon,&gps_speed,&gps_time_ms);
				#endif
				
				//get dht humidity
				#if WORK_MODE==0	//test mode
				dht_humidity = (uint16_t) random();
				#else //real mode
				dht_humidity = GetHumidity();
				#endif
				
				//get bmp data
				#if WORK_MODE==0	//test mode
				bmp_pressure+=100000;
				bmp_temperature+=100;
				bmp_altitude+=100;
				#else //real mode
				GetBMPData(&bmp_pressure, &bmp_temperature, &bmp_altitude);
				#endif
				
				//get pwr level
				pwr_level = GetPowerSupplyLevel();
				
				//send the data
				SendDataPayload(CMD_GET_DATA, gps_status, gps_lat, gps_lon, gps_time_ms, gps_speed, bmp_pressure, bmp_altitude, bmp_temperature, dht_humidity, pwr_level);
				
				//delay a bit
				_delay_ms(500);
				break;
				
				default:
				uart_cmd[0] = STATUS_CMD_UNKNOWN;
				uart_send_reply(MASTER_ID, CMD_STATUS,1,&uart_cmd[0]);
				break;
			}
		}
	}

	return 0;
}