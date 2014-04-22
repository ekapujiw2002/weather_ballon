/*
* balon_udara.c
*
* Created: 1/22/2014 11:07:46 AM
*  Author: EX4
*/

//standar lib
#include <avr/io.h>
#include <stdio.h>
#include <util/delay.h>

//lib
#include "lib/uart/usart_lib.h"
//#include "lib/sht11/sht11.h"

#include "lib/1wire/crc8.h"
#include "lib/1wire/onewire.h"
#include "lib/1wire/ds18x20.h"

//data struct
//temperature data
//typedef struct tsense{
	//uint8_t sign;
	//uint8_t cel;
	//uint8_t frac;
	//uint8_t sub;
//} DS18B20_DATA;

//max number of themperature sensors
#define MAXSENSORS 1
//temperature variable
DS18B20_DATA TempC;
//sensor ID array
uint8_t gSensorIDs[MAX_SENSORS_NUM][OW_ROMCODE_SIZE];

//read attached ds
//return how many ds detected
uint8_t SearchDS18B20(void)
{
	uint8_t i;
	uint8_t id[OW_ROMCODE_SIZE];
	uint8_t diff, Sensors;
	Sensors = 0;
	for( diff = OW_SEARCH_FIRST;
	diff != OW_LAST_DEVICE && Sensors < MAX_SENSORS_NUM ; )
	{
		DS18X20_find_sensor( &diff, &id[0] );
		
		if( diff == OW_PRESENCE_ERR ) {
			break;
		}
		
		if( diff == OW_DATA_ERR ) {
			break;
		}
		
		for (i=0;i<OW_ROMCODE_SIZE;i++)
		gSensorIDs[Sensors][i]=id[i];
		Sensors++;
	}
	return Sensors;
}

//read temp ds18s20
float ReadDS1820Temp(uint8_t aIDSensor)
{
	uint8_t i, fr;
	float fx;
	DS18B20_DATA TempCx;
	
	i = aIDSensor;// with ID
	DS18X20_start_meas( DS18X20_POWER_EXTERN, NULL );
	_delay_ms(DS18B20_TCONV_12BIT);
	
	//reading temperature data
	DS18X20_read_meas_single(i, &TempCx.sub, &TempCx.cel, &fr);
	
	//recalculating fractional part
	TempCx.frac=(uint8_t)((fr*DS18X20_FRACCONV)/100);
	
	//as float
	fx = (float)(TempCx.cel + ((float)TempCx.frac/100));
	
	//sign adjust
	if (TempCx.sub==1)
	{
		TempCx.sign='-';
		fx *= -1;
	}		
	else
		TempCx.sign='+';
		
	return fx;
}

//main program
int main(void)
{
	//struct sht11_t dataset;
	float ftemp;
	
	stdin = stdout = &USARTInputOutputStream;
	
	//powerup delay
	_delay_ms(100);
	
	//init usart
	USART_Init(BAUD_9600,COM_CH0,PARITY_NONE,STOP_BIT_1,DATA_BIT_8);
	
	//init sht11
	//printf("SHT11 TEST\rInit...\r");
	//
	//sht11_init(&dataset);
	
	//cek ok or not
	//if (dataset.status_reg_crc8 && (dataset.status_reg_crc8 == dataset.status_reg_crc8c)) {
		//printf("device ok...\r");
	//} else {
		//printf("device not detected\r");
	//}
	
	//init temperature sensor
	printf("find %d DS1820 with ID = ", SearchDS18B20());
	
	uint8_t ix;
	for (ix=8;ix>0;ix--)
	{
		printf("%02x", gSensorIDs[0][ix-1]);
	}
	printf("\r");
	
	//while(1);
	
	while(1)
	{
		//TODO:: Please write your application code
		//sht11_read_all (&dataset);
		//
		//printf("RH = %.3f\r", dataset.humidity_compensated);
		
		ftemp = ReadDS1820Temp(gSensorIDs[0][0]);
		//ReadDS1820Temp();
		
		printf("%.2f%cC\r", ftemp, 0xBA);
		
		_delay_ms(500);
	}
}