
# Morph Plugin

General Morph Plugin for Controlling Automation and Interpolating Between Values
 
This is a general plugin that allows one automation lane to control multiple other automation lanes.  For each target lane, it can store up to ten automation values and can interpolate between them using the main controller's slider.

Before describing how it all works, here is a quick demo video of constructing a multiband delay and controlling it with Morph plugins.  An original signal (simple guitar chords, far left track) is split into eight tracks, each one containing a Morph Locator and an ACE Delay plugin.  Morph Controllers then target each of the eight ACE Delays in order to control their delay times and feedback strengths.  The first half of the video shows the way that parameters are linked, and the second half contains an audio example of the multiband delay in practice.  (Audio starts at 1:20 and is loud.)  Note that everything here could be done using normal automation without the Morphs, but the Morphs make the desired values much more convenient to hit and reduce the 16 automatable parameters down to two.  With only two parameters, they can be mapped easily to a midi controller and played live.

[![](https://img.youtube.com/vi/5uT9pQQBtcI/0.jpg)](https://youtu.be/5uT9pQQBtcI "Morph Plugin for Ardour")

## Basic Usage / Architecture Overview

As it stands currently, the "plugin" consists of three separate pieces of lua code.  Two are dsp processors and the third is a session script.  The dsp processors are simply containers of values and do no processing.  All of the processing is actually in the session script.  

1.  morph_locator.lua is an incredibly simple dsp processor that has exactly one parameter: locator_ID.  This plugin needs to be placed in a track immediately before the desired target plugin.  Manually ensure that every Morph Locator has a unique locator_ID set.  (But note that multiple Morph Controllers can target the same Morph Locator.)

2.  morph_controller.lua has a large number of parameters.  
    - The very first parameter is the controller value that slides between 0 and 1.  
    - The remaining 14 parameters are replicated once for each of 8 targets.  
    - The __target_plugin_id parameter should be set to the same value as the locator_ID of a Morph Locator in order to control the target.  
    - The parameter __target_nth_param determines which of the target's parameters is to be controlled.  
    - The __target_enabled parameter determines whether this target's automation is controlled or not.  
    - The remaining parameters store up to 10 values for the target automation lane, and the target_control_point_count parameter dictates how many of those 10 values are interpolated between as the main controller slides between 0 and 1.
    - Note: the parameter names have been shortened so that more parameters fit on the screen in Ardour's generic UI.  con, ti_ct for count, ti_c0, ti_c1, ..., ti_c9, ti_pid, ti_nth, and ti_ena

3.  morph_lane_linker.lua is a session script that, upon loading, finds all Morph Locators, all plugins immediately following Morph Locators, and all Morph Controllers, and then uses the configurations of the Morph Locators and Controllers to write automation values into the desired targets.  This script should need no intervention except to be loaded.  For convenience, it prints out all automatable parameters for every unique plugin in the session. Check the output log for messages.  Note that it configures all of the Morph Controllers and Locators once upon initially loading the script and then once again every 5 seconds that the transport is not active.

4.  BONUS: morph_controller.lua can be configured as a low-frequency oscillator.  When USE LFO? is enabled, then the Controller's value will be automatically modulated by the LFO.
    - shape: choose between sine and saw
    - freq (Hz): the speed of the LFO in cycles per second
    - beat div: the speed of the LFO in terms of the current transport location's tempo.  Can specify the speed of a whole measure (1/1), half measure (1/2), quarter note (1/4), quarter note triplet (1/4T), etc.
    - speed mode: choose to use freq (Hz) or beat div when determining LFO speed
    - phase (deg): the starting phase of the LFO
    - reset: set to 0 for enabling the LFO to run, and set to 1 to force the LFO to be stopped at the configured phase.
    - USE LFO?: set to 1 to enable LFO control.  Set to 0 to disable the LFO for this Controller.
[![](https://img.youtube.com/vi/JN4jlhjcwRE/0.jpg)](https://youtu.be/JN4jlhjcwRE "Morph Controller with LFO for Ardour")

## "Installation"

Copy the three Lua scripts into the appropriate folder.  For me on linux, that folder is ~/.config/ardour7/scripts

Afterwards, launching Ardour should show Morph Locator and Morph Controller in the list of plugins that can be added to a track.  Add and configure those as necessary.  To run the session script, go to the Edit menu in the toolbar, hover Lua Scripts, select Script Manager.  In the window that appears, click on the Session tab, then Load the Morph Lane Linker script.

## Thoughts, Discussions, Why

This type of functionality would be amazing to have built into Ardour directly.  I saw online a recent interview with Robin where he teased (teased is too strong a word even) that automation control might possibly be starting development in a couple years.  And as of late, I have been using Vital and Surge XT synths in my own music making, both of which have extremely strong modulation capabilities, so much so that I find myself trying to do more and more work in the synths themselves rather than in the DAW.  Vital's mod remap is especially lovely.

A full deep-dive into automatable automation would definitely be a ton of work for Ardour or any DAW.  The Morph plugin here provides a very simple/crude approximation of some of those features.

The Locators are needed because Ardour's IDs for plugins seems to change at random times.

Sometimes the session script does not appear to be running unless the transport is acting.  Unsure why.

This does not play well with the has-been-modified asterisk next to the filename in the titlebar indicating that the project has changed.  Notice in the video that the two Morph Controllers' controllers have their automation modes set to Play (making their sliders gray in the mixer strips) but the ACE Delays are set to Manual (and thus their sliders in the mixer strips remain blue as though they could be adjusted).

Is this zipper friendly?  No clue!  Close enough for my purposes.  What's the update frequency?  Also no clue!

What am I hearing in the demo?  Raw direct input from my guitar as I strummed some chords is processed by a make-shift multiband delay.  Based on settings, the multiband delay can delay specific frequency bands more than others.  The spectrogram on the original signal shows all of the frequencies arriving simultaneously on every chord strum, but the output signal's spectrogram on the far right shows that different frequencies get spread out.  Audibly, the first four chord strikes are unmodified, and the effect begins on the fifth chord.  For the first few effected chords, the low frequency parts are delayed less than the high frequency parts, so the bass swells and precedes the sharper snap of the transient.  Later on in the demo, the delay times are varied, and feedback in the whole setup makes everything even more chaotic.

## Huge Drawback to Current Solution

Because the main component is a "session" script, it requires a session in order to operate.  As far as I can tell, that means that morph_lane_linker.lua does not run when exporting a project, regardless of whether freewheeling or real-time exporting.  The solution for now is to record / bounce the audio into a track and then use the recorded region instead of the automatable setup.

## TODO and Immediate Future

- linear interpolation vs discrete steps
- If you have better names for anything here, let me know.  Nothing is set in stone.

### Distant Future

- Modify morph_lane_linker.lua to constantly watch the project and auto-configure itself as necessary instead of relying on unload/reload

This is tentatively done!  The morph_lane_linker.lua script checks the entire session once every 5 seconds while the transport is not running.  Please let me know if you run into memory issues.
[![](https://img.youtube.com/vi/fxkiRIib1u0/0.jpg)](https://youtu.be/fxkiRIib1u0 "Live reload for morph lane linker")

- Is there a way to do automated / unit tests on Lua code?  Would it be possible to get a headless Ardour session that could run all of the components such that I could automate creating a track, creating a plugin, loading the Morph stuff, changing values, and ensuring that the appropriate automatables have the correct values?
- Is it possible for a Lua DSP processor (or any processor, for that matter) to access the Session and Ardour.LuaAPI objects in the dsp_run method?  If so, then all of the morph_lane_linker code could be moved into the morph_processor to eliminate the session script.

#### Even Distanter Future

- GUI
- Can this kind of functionality be built into Ardour directly?

## Inspirations

FL's Multiband Delay (with Morph knob at 4:30) https://www.youtube.com/watch?v=GGixzSy7SGM
Morph EQ (a whole plugin completely unrelated to the work here) https://www.youtube.com/watch?v=Cy1gwB62CFo

## Closing Thoughts

This is currently a bit awkward to use, but it's good enough for me personally.  I might modify it a bit as I find more capabilities that need to be covered, but if you use it and have suggestions, let me know!

The Lua stuff was surprisingly hard to figure out, but the massive number of scripts in Ardour's github repo were incredibly, incredibly helpful.

I am really enjoying my time with Ardour!  Music is fun.

Here's a link to the repo where you can find the three lua components.  https://github.com/rrastgoufard/Morph_Ardour
