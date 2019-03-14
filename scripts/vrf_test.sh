#!/usr/bin/expect -f
 
set timeout -1
set count 0
set prompt "root@qemux86-64:~#"
 
# SELinux should be disabled to enable the following tests
spawn newrole -r secadm_r -- -c "setenforce 0"

# Create the first VRF: vrf_1
expect "$prompt"
spawn vrf-create "1"
 
expect "Please choose:"
send -- "2\r"
expect "Select action:"
send -- "ADD\r"
expect "Enter the name of the new interface in the VRF or EXIT to quit:"
send -- "veth0\r"
expect "Select the physical link to map to VRF interface veth0 or EXIT to quit:"
send -- "eth0\r"
expect "Enter selection:"
send -- "MACVLAN\r"
expect "Enter selection:"
send -- "BRIDGE\r"
expect "Enter an IPv4 address for interface veth0 in the form xxx.xxx.xxx.xxx/yy\r"
send -- "11.22.33.44/24\r"
expect "Select action:"
send -- "SHOW\r"
expect "Select action:"
send -- "DONE\r"
expect "vrf_1 successfully created"

send -- "\ntest_case: vrf_1_create - pass\n"

expect "$prompt"
spawn vrf-status 1
expect "STOPPED"
 
# Start the first VRF
expect "$prompt"
spawn vrf-start 1
expect {
    "vrf_1 failed to start" {
        send_user "\ntest_case: vrf_1_start - fail\n"
        incr count

        expect "$prompt"
        spawn vrf-destroy 1
        expect "Enter YES to confirm or anything else to cancel:"
        send -- "YES\r"
        expect "vrf_1 successfully destroyed"
        send -- "\ntest_case: vrf_1_destroy - pass\n"
    }
    "vrf_1 successfully started" {
        send_user "\ntest_case: vrf_1_start - pass\n"
    }
}

expect "$prompt"
spawn vrf-status 1
expect "RUNNING"
 
# Create the second VRF: vrf_2
expect "$prompt"
spawn vrf-create 2
 
expect "Please choose:"
send -- "2\r"
expect "Select action:"
send -- "ADD\r"
expect "Enter the name of the new interface in the VRF or EXIT to quit:"
send -- "veth0\r"
expect "Select the physical link to map to VRF interface veth0 or EXIT to quit:"
send -- "eth0\r"
expect "Enter selection:"
send -- "MACVLAN\r"
expect "Enter selection:"
send -- "BRIDGE\r"
expect "Enter an IPv4 address for interface veth0 in the form xxx.xxx.xxx.xxx/yy\r"
send -- "11.22.33.46/24\r"
expect "Select action:"
send -- "SHOW\r"
expect "Select action:"
send -- "DONE\r"
expect "vrf_2 successfully created"

send -- "\ntest_case: vrf_2_create - pass\n"

# Add the second network interface to vrf_2 through vrf-attach
expect "$prompt"
spawn vrf-attach 2 -i -- /sbin/ifconfig
 
expect "Select action:"
send -- "ADD\r"
expect "Enter the name of the new interface in the VRF or EXIT to quit:"
send -- "veth1\r"
expect "Select the physical link to map to VRF interface veth1 or EXIT to quit:"
send -- "eth0\r"
expect "Enter selection:"
send -- "MACVLAN\r"
expect "Enter selection:"
send -- "BRIDGE\r"
expect "Enter an IPv4 address for interface veth1 in the form xxx.xxx.xxx.xxx/yy\r"
send -- "10.10.12.1/24\r"
expect "Select action:"
send -- "SHOW\r"
expect "Select action:"
send -- "DONE\r"
expect "vrf_2 is stopped, new config will take effect when it starts"

send -- "\ntest_case: vrf_2_add_veth1 - pass\n"

expect "$prompt"
spawn vrf-status 2
expect "STOPPED"

expect "$prompt"
spawn vrf-start 2
expect {
    "vrf_2 failed to start" {
        send_user "\ntest_case: vrf_2_start - fail\n"
        incr count

        expect "$prompt"
        spawn vrf-destroy 2
        expect "Enter YES to confirm or anything else to cancel:"
        send -- "YES\r"
        expect "vrf_2 successfully destroyed"
        send -- "\ntest_case: vrf_2_destroy - pass\n"

        expect eof
        exit
    }
    "vrf_2 successfully started" {
        send_user "\ntest_case: vrf_2_start - pass\n"
    }
}

expect "$prompt"
spawn vrf-status 2
expect "RUNNING"
expect "10.10.12.1"
expect "11.22.33.46"
 
expect "$prompt"
spawn vrf-attach 1
expect "Enter command and option attach to :"
send -- "\r"
 
expect "sh-4.4#"
send -- "ifconfig\r"
expect "inet addr:11.22.33.44"
expect "sh-4.4#"
send -- "route\r"
expect "sh-4.4#"
send -- "ping  11.22.33.46 -c 3\r"
expect {
    "0 received, 100% packet loss" {
        send_user "\ntest_case: vrf_1_attach_ping - fail\n"
        incr count
    }
    "3 received, 0% packet loss" {
        send_user "\ntest_case: vrf_1_attach_ping - pass\n"
    }
}
expect "sh-4.4#"
send -- "exit\r"
 
expect "$prompt"
send_user "\ntest_case: vrf_1_attach - pass\n"

spawn vrf-attach 2
expect "Enter command and option attach to :"
send -- "\r"
 
expect "sh-4.4#"
send -- "ifconfig\r"
expect "inet addr:11.22.33.46"
expect "inet addr:10.10.12.1"
expect "sh-4.4#"
send -- "ping  11.22.33.44 -c 3\r"
expect {
    "0 received, 100% packet loss" {
        send_user "\ntest_case: vrf_2_attach_ping - fail\n"
        incr count
    }
    "3 received, 0% packet loss" {
        send_user "\ntest_case: vrf_2_attach_ping - pass\n"
    }
}
expect "sh-4.4#"
send -- "exit\r"
 
expect "$prompt"
send_user "\ntest_case: vrf_2_attach - pass\n"

# Stop all VRFs
spawn vrf-stop 1
expect "vrf_1 successfully stopped"
send -- "\ntest_case: vrf_1_stop - pass\n"

expect "$prompt"
spawn vrf-status 1
expect "STOPPED"
 
expect "$prompt"
spawn vrf-destroy 1
expect "Enter YES to confirm or anything else to cancel:"
send -- "YES\r"
expect "vrf_1 successfully destroyed"
send -- "\ntest_case: vrf_1_destroy - pass\n"
 
expect "$prompt"
spawn vrf-stop 2
expect "vrf_2 successfully stopped"
send -- "\ntest_case: vrf_2_stop - pass\n"

expect "$prompt"
spawn vrf-status 2
expect "STOPPED"
 
expect "$prompt"
spawn vrf-destroy 2
expect "Enter YES to confirm or anything else to cancel:"
send -- "YES\r"
expect "vrf_2 successfully destroyed"
send -- "\ntest_case: vrf_2_destroy - pass\n"
 
expect "$prompt"
spawn vrf-status
 
expect eof
exit
