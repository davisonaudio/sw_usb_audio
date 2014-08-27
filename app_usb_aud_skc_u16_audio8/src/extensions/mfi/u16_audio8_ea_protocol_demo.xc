#ifdef IAP_EA_NATIVE_TRANS

#include "iap.h"
#include "ea_protocol_demo.h"
#include "gpio.h"
#include <platform.h>
#include <timer.h>

#define AUDIO8_BUTTON_1 0xE

on tile[AUDIO_IO_TILE]: in port p_buttons = PORT_BUTTON_GPIO;

void com_xmos_demo_led_ctrl_user(com_xmos_demo_led_ctrl_commands_t demo_command)
{
    if (demo_command == LED_OFF_CMD)
    {
        set_led_array_mask(LED_MASK_COL_OFF);
    }
    else
    {
        set_led_array_mask(LED_MASK_DISABLE);
    }
}

void u16_audio8_ea_protocol_demo(chanend c_ea_data)
{
    unsigned char current_val = 0xFF; // Buttons pulled up
    int is_stable = 1;
    timer tmr;
    const unsigned debounce_delay_ms = 50;
    unsigned debounce_timeout;

    while (1)
    {
        char data[IAP2_EA_NATIVE_TRANS_MAX_PACKET_SIZE];

        select //TODO: could use iAP2_EANativeTransport_dataToiOS() here - would need to update names etc. to keep it clear
        {
            case c_ea_data :> int dataLength:
                // Receive the data
                for (int i = 0; i < dataLength; i++)
                {
                    c_ea_data :> data[i];
                }
                usb_packet_parser(data, dataLength, c_ea_data);
                break;

            /* Button handler */
            // If the button is "stable", react when the I/O pin changes value
            case is_stable => p_buttons when pinsneq(current_val) :> current_val:
                if ((current_val | AUDIO8_BUTTON_1) == AUDIO8_BUTTON_1)
                {
                    // LED used for EA Protocol demo is on when the mask is disabled
                    if (get_led_array_mask() == LED_MASK_DISABLE)
                    {
                        // So turn it off now
                        set_led_array_mask(LED_MASK_COL_OFF);

                        // Send protocol message so this change of state is reflect correctly
                        process_user_input(0, c_ea_data);
                    }
                    else
                    {
                        // So turn it on now
                        set_led_array_mask(LED_MASK_DISABLE);

                        // Send protocol message so this change of state is reflect correctly
                        process_user_input(1, c_ea_data);
                    }
                }

                is_stable = 0;
                unsigned current_time;
                tmr :> current_time;
                // Calculate time to event after debounce period
                debounce_timeout = current_time + (debounce_delay_ms * (XS1_TIMER_HZ/1000));
                break;

            /* If the button is not stable (i.e. bouncing around) then select
             * when we the timer reaches the timeout to renter a stable period
             */
            case !is_stable => tmr when timerafter(debounce_timeout) :> void:
                is_stable = 1;
                break;
        }
    }
}

#endif /* IAP_EA_NATIVE_TRANS */
