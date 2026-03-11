/*
 * C runtime startup for armv7 (iOS 5.x)
 *
 * Extracted from Apple's open-source Csu-88/start.s
 * https://github.com/apple-oss-distributions/Csu/blob/Csu-88/start.s
 *
 * Copyright (c) 1999-2009 Apple Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * Portions Copyright (c) 1999 Apple Computer, Inc.  All Rights
 * Reserved.  This file contains Original Code and/or Modifications of
 * Original Code as defined in and that are subject to the Apple Public
 * Source License Version 1.1 (the "License").  You may not use this file
 * except in compliance with the License.  Please obtain a copy of the
 * License at http://www.apple.com/publicsource and read it before using
 * this file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON- INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

/*
 * Kernel sets up stack frame to look like:
 *
 *      | STRING AREA |
 *      +-------------+
 *      |      0      |
 *      +-------------+
 *      |  exec_path  | extra "apple" parameters start after NULL terminating env array
 *      +-------------+
 *      |      0      |
 *      +-------------+
 *      |    env[n]   |
 *      +-------------+
 *             :
 *      +-------------+
 *      |    env[0]   |
 *      +-------------+
 *      |      0      |
 *      +-------------+
 *      | arg[argc-1] |
 *      +-------------+
 *             :
 *      +-------------+
 *      |    arg[0]   |
 *      +-------------+
 *      |     argc    |
 *      +-------------+ <- sp
 */

	.text
	.globl start
	.align 2

start:
	ldr	r0, [sp]		// get argc into r0
	add	r1, sp, #4		// get argv into r1
	add	r4, r0, #1		// calculate argc + 1 into r4
	add	r2, r1, r4, lsl #2	// get address of env[0] into r2
	bic	sp, sp, #15		// force sixteen-byte alignment

	// Scan past env[] array to find "apple" parameters
	mov	r3, r2
Lapple:
	ldr	r4, [r3], #4		// look for NULL ending env[] array
	cmp	r4, #0
	bne	Lapple
					// "apple" param now in r3

	bl	_main
	b	_exit
