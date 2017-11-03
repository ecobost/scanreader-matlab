# scanreader-matlab
Matlab TIFF Stack Reader for ScanImage 5 scans (including multiROI).

We treat a scan as a collection of recording fields: rectangular planes at a given x, y, z position in the scan recorded in a number of channels during a preset amount of time. All fields have the same number of channels and number of frames.

We plan to support new versions of ScanImage scans as our lab starts using them. If you would like us to add support for an older (or different) version of ScanImage, send us a small sample scan.

### Installation
Make the +scanreader/ package folder accesible to Matlab.

### Usage
```matlab
scan = scanreader.readscan('/data/my_scan_*.tif')
print(scan.version)
print(scan.nFrames)
print(scan.nChannels)
print(scan.nFields)

for i = 1:scan.nFields
    field = scan(i, :, :, :, :)
    % process field (4-d array: [y, x, channels, frames])
    clear field % free memory before next iteration
end

x = scan() % 5-d array [fields, y, x, channel, frames]
y = scan(1:2, :, :, 1, end-999: end) % 5-d array: last 1000 frames of first 2 fields on the first channel
z = scan(2, :, :, :, :) % 4-d array: the second field (over all channels and time)

scan = scanreader.read_scan('/data/my_scan_*.tif', 'float32', true)
% scan loaded as float32 (default is int16) and adjacent fields at same depth will be joined.
```
Scan objects (returned by `readscan()`) are indexable (as shown). Indexes can be arrays of positive integers or ':'. It should act like a Matlab 5-d array (with added automatic squeezing of single valued dimensions)---no linear or boolean indexing, though.

This is a Matlab port of [atlab/scanreader](https://github.com/atlab/scanreader), originally in Python.
