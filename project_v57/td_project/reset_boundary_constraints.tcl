# Run in TD's main Tcl interpreter after placement. Persist only standard SDC
# commands with literal pin names; TD's SDC interpreter cannot run object queries
# such as get_property DIRECTION consistently.
proc v39_write_reset_boundary {filename} {
 set net [get_nets -hier -quiet {u_hdmi2phy_wrapper/serial_control/serial_reset/async_reset}]
 if {[llength $net]!=1} {error "Missing serial-reset synchronizer input net"}
 set all [get_pins -of $net];set names {}
 foreach name $all {
  set pin [get_pins $name]
  set direction [get_property DIRECTION $pin]
  if {$direction eq "0" || $direction eq "input" || $direction eq "IN"} {
   if {![string match *.sr $name]} {error "Unexpected non-SR consumer: $name"}
   lappend names $name
  }
 }
 if {[llength $names]<4 || [llength $names]>16} {error "Unexpected reset synchronizer replication; inspect chain"}
 set f [open $filename w]
 puts $f "# Only incoming SR terminals of the four-stage serial-reset synchronizer."
 foreach name $names {puts $f [format {set_false_path -to [get_pins {%s}]} $name]}
 close $f
 # TD does not reload newly registered SDC files once its timer exists.
 # Apply the same literal set through the main interpreter as well. This is
 # a timing constraint, never a logic/cell modification.
 set_false_path -to [get_pins $names]
 puts "V39_RESET_BOUNDARY_SR_COUNT=[llength $names]"
}
