/* Stage 1.1 "hello xiangshan" (XiangShanLab question bank, primary task 1):
 *
 *   hello xiangshan, I am <name>, from <school>, in <IP address>
 *
 * Bare-metal program for the XiangShan emu and NEMU. Name, school and the IP
 * address of the machine running the environment are injected at build time
 * by the Makefile (HELLO_NAME / HELLO_SCHOOL / HELLO_IP; the IP defaults to
 * the source address of the host's default route). Output goes to the
 * uartlite TX register at 0x40600004, which both simulators print to stdout.
 */
#include <stdint.h>

#ifndef HELLO_NAME
#define HELLO_NAME "xxx"
#endif
#ifndef HELLO_SCHOOL
#define HELLO_SCHOOL "xxx"
#endif
#ifndef HELLO_IP
#define HELLO_IP "0.0.0.0"
#endif

#define UART_TX ((volatile uint8_t *)0x40600004UL)
static void puts_(const char *s) { while (*s) *UART_TX = (uint8_t)*s++; }

int main(void) {
  puts_("hello xiangshan, I am " HELLO_NAME ", from " HELLO_SCHOOL ", in " HELLO_IP "\n");
  return 0;
}
