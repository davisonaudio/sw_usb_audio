#include <platform.h>
#include <xs1_su.h>
#include "devicedefines.h"
#include "hostactive.h"
#include "audiostream.h"

#ifdef USB_SEL_A
#include <hwtimer.h>
#include "interrupt.h"
hwtimer_t g_rebootTimer;

#pragma select handler
void HandleRebootTimeout(timer t)
{
    unsigned time;
    t :> time;

    /* Reset U8 device */
    write_node_config_reg(usb_tile, XS1_SU_CFG_RST_MISC_NUM, 1);
    while(1);

}

#define REBOOT_TIMEOUT 20000000

void XUD_UserSuspend(void)
{
    unsigned time;

    UserAudioStreamStop();
    UserHostActive(0);

    DISABLE_INTERRUPTS();

    g_rebootTimer :> time;
    time += REBOOT_TIMEOUT;

    asm("setd res[%0], %1"::"r"(g_rebootTimer),"r"(time));
    asm("setc res[%0], %1"::"r"(g_rebootTimer),"r"(XS1_SETC_COND_AFTER));

    set_interrupt_handler(HandleRebootTimeout, 200, 1, g_rebootTimer, 0)
}

void XUD_UserResume(void)
{
    unsigned config;

    /* Clear the reboot interrupt */
    DISABLE_INTERRUPTS();
    asm("edu res[%0]"::"r"(g_rebootTimer));

    asm("ldw %0, dp[g_currentConfig]" : "=r" (config):);

    if(config == 1)
    {
        UserHostActive(1);
    }
}

#endif