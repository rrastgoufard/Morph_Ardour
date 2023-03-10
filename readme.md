
# Morph Controller (ver2)

General Morph Controller for Controlling Automation and Interpolating Between Values
 
This is a general plugin for Ardour that allows one automation lane to control multiple other automation lanes.  For each target lane, it can store up to ten automation values and can interpolate between them using the main controller's slider.

Before describing how it all works, here is a quick demo video of constructing a multiband delay and controlling it with Morph plugins.  An original signal (simple guitar chords, far left track) is split into eight tracks, each one containing a Morph Locator and an ACE Delay plugin.  Morph Controllers then target each of the eight ACE Delays in order to control their delay times and feedback strengths.  The first half of the video shows the way that parameters are linked, and the second half contains an audio example of the multiband delay in practice.  (Audio starts at 1:20 and is loud.)  Note that everything here could be done using normal automation without the Morphs, but the Morphs make the desired values much more convenient to hit and reduce the 16 automatable parameters down to two.  With only two parameters, they can be mapped easily to a midi controller and played live.

[![](https://img.youtube.com/vi/5uT9pQQBtcI/0.jpg)](https://youtu.be/5uT9pQQBtcI "Morph Plugin for Ardour")

## Basic Usage / Architecture Overview

As it stands currently, the "plugin" consists of two pieces of lua code, one being the Morph Locator that targets a desired plugin on a track, and the second being the Morph Controller that does all of the parameter automation.

1.  morph_locator.lua is an incredibly simple dsp processor that has exactly one parameter: locator_ID.  This plugin needs to be placed in a track immediately before the desired target plugin.  Manually ensure that every Morph Locator has a unique locator_ID set.  (But note that multiple Morph Controllers can target the same Morph Locator.)  

The Morph Locator's inline UI displays its own Locator ID as well as the target's parameter number of the last parameter that was modified.  These two numbers correspond to the pid and nth entries needed in a Morph Controller.  
![2023_01_30_morph_locator_touch](https://user-images.githubusercontent.com/23608928/215411098-73f94d7c-64e9-404b-86e7-2324500ab061.gif)


2.  morph_controller.lua has a large number of parameters.  

Controller: the controller value that slides between 0 and 1.  

Visualize: choose to visualize an overview of all target outputs by setting to -1, or choose a specific target by setting in the range of 0 to 7.

Control Mode: choose one of Manual, Use LFO, Audio Input, or Zero Crossings.  When set to Zero Crossings, the Controller's value is proportional to the detected frequency of the input audio, as detected by the number of zero crossings.  (This is a crude method of frequency tracking.)  When set to Audio Input, the peak level of the input (clipped to the range 0 to 1) will determine the Controller's value.  When set to Use LFO, the following parameters LFO parameters will take effect.

lfo shape: choose between sine and saw

lfo freq (Hz): the speed of the LFO in cycles per second

lfo beat div: the speed of the LFO in terms of the current transport location's tempo.  Can specify the speed of a whole measure (1/1), half measure (1/2), quarter note (1/4), quarter note triplet (1/4T), etc.

lfo speed mode: choose to use freq (Hz) or beat div when determining LFO speed

lfo phase (deg): the starting phase of the LFO

lfo reset: set to 0 for enabling the LFO to run, and set to 1 to force the LFO to be stopped at the configured phase.  

[![](https://img.youtube.com/vi/JN4jlhjcwRE/0.jpg)](https://youtu.be/JN4jlhjcwRE "Morph Controller with LFO for Ardour")

audio +smooth: time constant for smoothing out changes that increase the Controller's value.  Lower gives faster response.

audio -smooth: time constant for smoothing out changes that decrease the Controller's value.  Lower gives faster response.

zx thresh: the level of the signal above which zero crossings are counted.  This is largely in place to prevent the noise floor from causing havoc on the frequency reading.

zx max (Hz): the maximum frequency to detect.  This is used to scale the Controller's value.

zx +smooth: when above the threshold zx thresh, this parameter determines how quickly the frequency reading is allowed to change.

zx -smooth: when below the threshold zx thresh, the reported frequency is designed to be zero, and this parameter determines how quickly the Controller's value is allowed to decay down to zero.  

The remaining 14 parameters are replicated once for each of 8 targets.  

The __target_plugin_id parameter should be set to the same value as the locator_ID of a Morph Locator in order to control the target.  

The parameter __target_nth_param determines which of the target's parameters is to be controlled.  

The __target_enabled parameter determines whether this target's automation is controlled or not.  

The __target_linear parameter allows switching between linear interpolation or discrete selection when going through different values.  Using discrete will allow step sequencing.

The __target_skew parameter skews, bends, or stretches the transfer curve of the parameter.  Easiest to see this in action by setting Visualize to a skewed target.

The remaining parameters store up to 10 values for the target automation lane, and the target_control_point_count parameter dictates how many of those 10 values are interpolated between as the main controller slides between 0 and 1.

Note: the parameter names have been shortened so that more parameters fit on the screen in Ardour's generic UI.  con, ti_ct for count, ti_c0, ti_c1, ..., ti_c9, ti_pid, ti_nth, ti_ena, and ti_lin
    

## "Installation"

Copy the two Lua scripts into the appropriate folder.  For me on linux, that folder is ~/.config/ardour7/scripts

Afterwards, launching Ardour should show Morph Locator and Morph Controller in the list of plugins that can be added to a track.  Add and configure those as necessary.  Feel free to enable the inline UI for more feedback while configuring.

## Thoughts, Discussions, Why

This type of functionality would be amazing to have built into Ardour directly.  I saw online a recent interview with Robin where he teased (teased is too strong a word even) that automation control might possibly be starting development in a couple years.  And as of late, I have been using Vital and Surge XT synths in my own music making, both of which have extremely strong modulation capabilities, so much so that I find myself trying to do more and more work in the synths themselves rather than in the DAW.  Vital's mod remap is especially lovely.

A full deep-dive into automatable automation would definitely be a ton of work for Ardour or any DAW.  The Morph plugin here provides a very simple/crude approximation of some of those features.

The Locators are needed because Ardour's IDs for plugins seems to change at random times.

This does not play well with the has-been-modified asterisk next to the filename in the titlebar indicating that the project has changed.  Notice in the video that the two Morph Controllers' controllers have their automation modes set to Play (making their sliders gray in the mixer strips) but the ACE Delays are set to Manual (and thus their sliders in the mixer strips remain blue as though they could be adjusted).

Is this zipper friendly?  No clue!  Close enough for my purposes.  What's the update frequency?  Also no clue!

What am I hearing in the demo?  Raw direct input from my guitar as I strummed some chords is processed by a make-shift multiband delay.  Based on settings, the multiband delay can delay specific frequency bands more than others.  The spectrogram on the original signal shows all of the frequencies arriving simultaneously on every chord strum, but the output signal's spectrogram on the far right shows that different frequencies get spread out.  Audibly, the first four chord strikes are unmodified, and the effect begins on the fifth chord.  For the first few effected chords, the low frequency parts are delayed less than the high frequency parts, so the bass swells and precedes the sharper snap of the transient.  Later on in the demo, the delay times are varied, and feedback in the whole setup makes everything even more chaotic.

# (ver2)

This is version 2 of Morph Controller!  It is SIGNIFICANTLY better than the previous version.  (The old version has been moved to v1 just in case.)

The main difference is that now the two plugins are DSP processors.  This brings three huge benefits.
1)  They watch for updates on every buffer (at most a handful of milliseconds), meaning they are extremely responsive to changes in layout.  Deleting a plugin, moving a Locator, changing a target inside a Controller, etc, are all very fast.
2)  They run in all contexts, including when exporting a track.
3)  Inline UI.  The UI is incredibly informative and displays the mapping curve, parameter name, bypass state, and, if misconfigured, error state.

Here are some demos of Morph Controller (ver2) in action.

Overview of a session with audio.  (Audio starts immediately and is loud.)

[![](https://img.youtube.com/vi/QJV8wmCUhhQ/0.jpg)](https://youtu.be/QJV8wmCUhhQ "Morph Controller (ver2) for Ardour")


Demo of exporting a session.  (No audio.)

[![](https://img.youtube.com/vi/yrHkwRv3eDk/0.jpg)](https://youtu.be/yrHkwRv3eDk "Morph Controller (ver2) for Ardour -- Export Demonstration")


Demo of Audio Input.  (Audio starts immediately.)

[![](https://img.youtube.com/vi/7RXJHe8YjVM/0.jpg)](https://youtu.be/7RXJHe8YjVM "Morph Controller (ver2) for Ardour -- Audio Input")

Demo of Audio Input modulating LFO Speed.  (Audio starts immediately.)

[![](https://img.youtube.com/vi/lLiOCMRXTqY/0.jpg)](https://youtu.be/lLiOCMRXTqY "Morph Controller (ver2) for Ardour -- LFO Speed controlled by Guitar Audio Input")

Deprecated -- Demo of Zero Crossing counter.  (Audio is INCREDIBLY LOUD)
[![](https://img.youtube.com/vi/JgNGnTziygM/0.jpg)](https://youtu.be/JgNGnTziygM "Morph Controller (ver2) for Ardour -- Zero Crossings for Pitch-Dependent Effects")

Demo of Zero Crossing counter Second Attempt.  (Audio is INCREDIBLY LOUD and starts immediately)
[![](https://img.youtube.com/vi/OW-YikmFyEc/0.jpg)](https://youtu.be/OW-YikmFyEc "Morph Controller (ver2) for Ardour -- Zero Crossings for Pitch-Dependent Effects Second Attempt")



## Inspirations

FL's Multiband Delay (with Morph knob at 4:30) https://www.youtube.com/watch?v=GGixzSy7SGM
Morph EQ (a whole plugin completely unrelated to the work here) https://www.youtube.com/watch?v=Cy1gwB62CFo

## Closing Thoughts

The UI is very bright and not Ardour-like.  I'm okay with this for now.  All of the UI elements feel like post-it notes that are designed to draw attention to themselves in order to keep things organized.  (Of course, the UI is completely optional.)

I am really enjoying my time with Ardour!  Music is fun.

Here's a link to the repo where you can find the lua plugins.  https://github.com/rrastgoufard/Morph_Ardour

And here are links to the two threads on Ardour's forums.

Original -- https://discourse.ardour.org/t/morph-plugin-for-controlling-automation/108184

Version 2 -- https://discourse.ardour.org/t/morph-controller-ver2-for-controlling-automation/108231
