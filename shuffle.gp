#! /usr/bin/gnuplot -c
###                                                                         #
##  SPDX-License-Identifier: Apache-2.0
##
##  Copyright Ericsson AB 2026. All Rights Reserved.
##
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##
##      http://www.apache.org/licenses/LICENSE-2.0
##
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.
##

###
##  Author: Raimo Niskanen, Erlang/OTP
##
##  GnuPlot script that creates the plot windows for my presentation
##  "Do the List Shuffle".
##
##  Assuming this script is named "shuffle.gp" and is located
##  in the same directory as a benchmark data file from "shuffle.erl"
##  named "shuffle.dat"
##
##  The ending summary slide with all plots:
##  $ ./shuffle.gp shuffle.dat svg
##
##  That command plots all the algorithms.  The "svg" terminal type
##  writes a number of files "plot-*.svg" where "plot-time.svg"
##  is used in the ending slide.
##
##  The .svg files are simply inserted into the presentation file.
##
##  As an example, the first plot slide:
##  $ ./shuffle.gp shuffle.dat svg 1 2
##
##  That command plots just the first and the second algorithm,
##  with the "svg" terminal type (to the same set of files).
##  The file "plot-data-size.svg" is the first plot slide in the
##  presentation, and "plot-garbage.svg" is the second.  It is mainly
##  those files and "plot-time.svg" that are used in the presentation.
##
##  As an alternative, the "qt" terminal type can be used:
##  $ ./shuffle.gp shuffle.dat qt
##
##  That brings up a set of interactive terminals, corresponding
##  to the plot file set.  In each terminal one can click on
##  the legend for an algorithm which toggles show/hide for that plot.
##  "q" closes the terminal (and "i" toggles all plots).
##

if (ARGC < 2) {
    print "Missing arguments: PlotDataFile svg|qt [ PlotIndex1 PlotIndex2 ]"
    exit 1
}

### Plot data in datafile, written by `shuffle:gp/*`
datafile = ARG1
term_type = ARG2
if (term_type eq "svg") {
    set_term = "set term svg font \"DejaVu Sans,22\" size 1200,720"
    q = 0.5 # Linespoints point size
} else {
    if (term_type eq "qt") {
        set_term = "set term qt (t=t+1) font \"DejaVu Sans,22\" \
                    persist noctrl size 1200,720"
        q = 2 # Linespoints point size
    } else {
        print "Unknown terminal type: ", ARG2
        exit 1
    }
}

if (ARGC < 4) {
    p1 = 0
} else {
    p1 = int(real(ARG3))
    p2 = int(real(ARG4))
    i1 = p1 - 1
    i2 = p2 - 1
}

set datafile columnheaders
set grid
set logscale x
set xlabel "List Length"
set yrange [0:*]
set key top left

plot_curves = "         \
if (p1 == 0) {          \
    plot for [i=0:*]    \
        datafile index i using 1:(column(col)*mul)                  \
        title columnheader(1) with linespoints lt (i+1) lw 2 ps q   \
} else {    \
    plot    \
         datafile index i1 using 1:(column(col)*mul)    \
         title columnheader(1) with lines lt p1 lw 1,   \
         datafile index i2 using 1:(column(col)*mul)    \
         title columnheader(1) with lines lt p2 lw 2    \
}"

t = 0

# time
eval(set_term)
set title "List Shuffle (time)"
if (term_type eq "svg") set output "plot-time.svg"
set ylabel "Execution Time [µs / Element]"
col = "time"
mul = 1e6
eval(plot_curves)

mul = 1

# max_heap
eval(set_term)
set title "List Shuffle (max heap)"
if (term_type eq "svg") set output "plot-max-heap.svg"
set ylabel "Max Heap Size After GC [Words / Element]"
col = "max_heap"
eval(plot_curves)

# avg_heap
eval(set_term)
set title "List Shuffle (avg heap)"
if (term_type eq "svg") set output "plot-avg-heap.svg"
set ylabel "Average Heap Size After GC [ Words / Element ]"
col = "avg_heap"
eval(plot_curves)

# gc_size
eval(set_term)
set title "List Shuffle (gc size)"
if (term_type eq "svg") set output "plot-gc-size.svg"
set ylabel "Data Processed by GC [ Words / Element ]"
col = "gc_size"
eval(plot_curves)

# garbage
eval(set_term)
set title "List Shuffle (garbage)"
if (term_type eq "svg") set output "plot-garbage.svg"
set ylabel "Produced Garbage [Words / Element]"
col = "garbage"
eval(plot_curves)

# data_size
eval(set_term)
set title "List Shuffle (data size)"
if (term_type eq "svg") set output "plot-data-size.svg"
set ylabel "Data Container Size [Words / Element]"
col = "data_size"
eval(plot_curves)

# rand_cnt
eval(set_term)
set title "List Shuffle (rand cnt)"
if (term_type eq "svg") set output "plot-rand-cnt.svg"
set ylabel "PRNG Calls [ / Element ]"
col = "rand_cnt"
eval(plot_curves)

# Yield for all windows to be rendered
pause 0.1
