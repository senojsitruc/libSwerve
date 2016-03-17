//
//  CJHexDump.c
//  libSwerve
//
//  Created by Curtis Jones on 2016.03.16.
//  Copyright © 2016 Symphonic Systems, Inc. All rights reserved.
//

#include "CJHexDump.h"

void
hexdump (const uint8_t *buf, int len)
{
	int i, j, k;
	
	printf("     -------------------------------------------------------------------------------\n");
	
	for (i = 0; i < len;) {
		printf("     ");
		
		for (j = i; j < i + 8 && j < len; j++)
			printf("%02x ", (unsigned char)buf[j]);
		
		// if at this point we have reached the end of the packet data, we need to
		// pad this last line such that it becomes even with the rest of the lines.
		if (j >= len - 1) {
			for (k = len % 16; k < 8; k++)
				printf("   ");
		}
		
		printf("  ");
		
		for (j = i + 8; j < i + 16 && j < len; j++)
			printf("%02x ", (unsigned char)buf[j]);
		
		// if at this point we have reached the end of the packet data, we need to
		// pad this last line such that it becomes even with the rest of the lines.
		if (j >= len - 1) {
			for (k = 16; k > 8 && k > len % 16; k--)
				printf("   ");
		}
		
		printf("  |  ");
		
		for (j = i; j < i + 16 && j < len; j++) {
			if ((int)buf[j] >= 32 && (int)buf[j] <= 126)
				printf("%c", (unsigned char)buf[j]);
			else
				printf(".");
		}
		
		printf("\n");
		i += 16;
	}
	
	printf("     -------------------------------------------------------------------------------\n");
}
