classdef ScanMultiROI < scanreader.scans.BaseScan
    % SCANMULTIROI An extension of ScanImage v5 that manages multiROI data (output from
    % mesoscope).
    
    properties (SetAccess = private)
        joinContiguous % bool. Whether contiguous fields are joined into one.
        rois % list of ROI objects (defined in +multiroi)
        fields % list of field objects (defined in +multiroi)
    end
    properties (SetAccess = private, Dependent) % inherited abstract properties
        nFields % number of fields
        fieldDepths % scaning depths per field
    end
    properties (SetAccess = private, Dependent)
        fieldWidths % array with field widths
        fieldHeights % array with field heights
        nRois % number of ROI volumes
        fieldRois % list of ROIs per field
        nFlyToLines %  number of lines between images in tiff page
        fieldHeightsInMicrons
        fieldWidthsInMicrons
    end
    properties (SetAccess = private, Dependent, Hidden)
        flyToSeconds % number of seconds it takes to move from one field to the next
    end
    
    methods
        function obj = ScanMultiROI(joinContiguous)
            obj@scanreader.scans.BaseScan() % call constructor in superclass
            if nargin > 0
                obj.joinContiguous = joinContiguous;
            else
                obj.joinContiguous = false;
            end
        end
        
        function nFields = get.nFields(obj)
            nFields = length(obj.fields);
        end
        
        function fieldDepths = get.fieldDepths(obj)
            fieldDepths = arrayfun(@(field) field.depth, obj.fields);
        end

        function fieldWidths = get.fieldWidths(obj)
            fieldWidths = arrayfun(@(field) field.width, obj.fields);
        end
        
        function fieldHeights = get.fieldHeights(obj)
            fieldHeights = arrayfun(@(field) field.height, obj.fields);
        end
        
        function nRois = get.nRois(obj)
            nRois = length(obj.rois);
        end
        
        function fieldRois = get.fieldRois(obj)
            fieldRois = arrayfun(@(field) field.roiId, obj.fields);
        end
        
        function flyToSeconds = get.flyToSeconds(obj)
            pattern = 'hScan2D\.flytoTimePerScanfield = (.*)';
            match = regexp(obj.header, pattern, 'tokens', 'dotexceptnewline');
            if ~isempty(match) flyToSeconds = str2double(match{1}{1}); end
        end
        
        function nFlyToLines = get.nFlyToLines(obj)
            % Number of lines recorded in the tiff page while flying to a different field,
            % i.e., distance between fields in the tiff page."""
            nFlyToLines = obj.flyToSeconds / obj.secondsPerLine;
            nFlyToLines = ceil(nFlyToLines);
            if obj.isBidirectional
                % line scanning always starts at one end of the image so this has to be even
                nFlyToLines = nFlyToLines + mod(nFlyToLines, 2);
            end
        end
        
        function fieldHeightsInMicrons = get.fieldHeightsInMicrons(obj)
            fieldHeightsInDegrees = arrayfun(@(field) field.heightInDegrees, obj.fields);
            fieldHeightsInMicrons = arrayfun(@obj.degreestomicrons, fieldHeightsInDegrees);
        end
        
        function fieldWidthsInMicrons = get.fieldWidthsInMicrons(obj)
            fieldWidthsInDegrees = arrayfun(@(field) field.widthInDegrees, obj.fields);
            fieldWidthsInMicrons = arrayfun(@obj.degreestomicrons, fieldWidthsInDegrees);
        end
        
        function readdata(obj, filenames, classname)
            % READDATA Set the header, create rois and fields (joining them if necessary).
            readdata@scanreader.scans.BaseScan(obj, filenames, classname)
            obj.rois = obj.createrois();
            obj.fields = obj.createfields();
            if obj.joinContiguous obj.joincontiguousfields(); end
        end
        
        function sliceId = fieldtoslice(obj, fieldId)
            % FIELDTOSLICE Given a field id return the corresponding slice id.
            field_ = obj.fields(fieldId);
            sliceId = find(obj.scanningDepths == field_.depth);
        end
        
        function index = end(obj, dim, ~)
            switch dim
                case 1 % fields
                    index = obj.nFields;
                case 2 % y
                    if all(obj.fieldHeights == obj.fieldHeights(1))
                        index = obj.fieldHeights(1);
                    else
                        error('end:IndexError', 'cannot use end for fields of different heigths')
                    end
                case 3 % x
                    if all(obj.fieldWidths == obj.fieldWidths(1))
                        index = obj.fieldWidths(1);
                    else
                        error('end:IndexError', 'cannot use end for fields of different widths')
                    end
                case 4 % channels
                    index = obj.nChannels;
                case 5 % frames
                    index = obj.nFrames;
                otherwise
                    index = 1;
            end
        end
            
    end
    
    methods(Hidden)
        function item = getitem(obj, key)
            % Fill key to size 5 (raises IndexError if more than 5)
            fullKey = scanreader.utils.fillkey(key, 5);
            
            % Check index types are valid
            for i = 1:length(fullKey)
                index = fullKey{i};
                scanreader.utils.checkindextype(i, index)
            end
            
            % Check each dimension is in bounds 
            scanreader.utils.checkindexisinbounds(1, fullKey{1}, obj.nFields)
            for fieldId = scanreader.utils.listifyindex(fullKey{1}, obj.nFields)
                scanreader.utils.checkindexisinbounds(2, fullKey{2}, obj.fieldWidths(fieldId))
                scanreader.utils.checkindexisinbounds(3, fullKey{3}, obj.fieldWidths(fieldId))
            end
            scanreader.utils.checkindexisinbounds(4, fullKey{4}, obj.nChannels)
            scanreader.utils.checkindexisinbounds(5, fullKey{5}, obj.nFrames)
            
            % Get slices/scanning_depths, channels and frames as lists
            fieldList = scanreader.utils.listifyindex(fullKey{1}, obj.nFields);
            yLists = arrayfun(@(fieldId) scanreader.utils.listifyindex(fullKey{2}, ...
                obj.fieldHeights(fieldId)), fieldList, 'uniformOutput', false);
            xLists = arrayfun(@(fieldId) scanreader.utils.listifyindex(fullKey{3}, ...
                obj.fieldWidths(fieldId)), fieldList, 'uniformOutput', false);
            channelList = scanreader.utils.listifyindex(fullKey{4}, obj.nChannels);
            frameList = scanreader.utils.listifyindex(fullKey{5}, obj.nFrames);
           
            % Edge case when slice gives 0 elements or index is empty list, e.g., scan(10:0)
            if isempty(fieldList) || any(cellfun(@isempty, yLists)) || any(cellfun(@isempty, xLists)) ...
                    || isempty(channelList) || isempty(frameList)
                item = double.empty();
                return
            end
            
            % Check output heights and widths match for all fields
            if ~all(cellfun(@(yList) length(yList) == length(yLists{1}), yLists))
                error('getitem:FieldDimensionMismatch', 'Image heights for all fields do not match')
            end
            if ~all(cellfun(@(xList) length(xList) == length(xLists{1}), xLists))
                error('getitem:FieldDimensionMismatch', 'Image widths for all fields do not match')
            end
            
            % Read the required pages
            sliceList = arrayfun(@obj.fieldtoslice, fieldList);
            pages = obj.readpages(sliceList, channelList, frameList);
            
            % Slice each field (this is not so memory efficient)
            outputShape = [length(fieldList), length(yLists{1}), length(xLists{1}), ...
                length(channelList), length(frameList)];
            item = zeros(outputShape, obj.classname);
            for i = 1:length(fieldList)
                fieldId = fieldList(i);
                field = obj.fields(fieldId);
                yList = yLists{i};
                xList = xLists{i};
                
                % Over each subfield in field (only one for non-contiguous fields)
                for j = 1:length(field.xSlices)
                    ySlice = field.ySlices{j};
                    xSlice = field.xSlices{j};
                    outputYSlice = field.outputYSlices{j};
                    outputXSlice = field.outputXSlices{j};
                                        
                    % Get y, x indices that need to be accessed in this subfield
                    yInSubfieldIndices = yList >= outputYSlice(1) & yList <= outputYSlice(end);
                    xInSubfieldIndices = xList >= outputXSlice(1) & xList <= outputXSlice(end);
                    ys = yList(yInSubfieldIndices) - outputYSlice(1) + ySlice(1);
                    xs = xList(xInSubfieldIndices) - outputXSlice(1) + xSlice(1);
                    
                    item(i, yInSubfieldIndices, xInSubfieldIndices, :, :) = pages(i, ys, xs, :, :);
                end
            end

            % If original index was a single integer delete that axis
            if ~isempty(key)
                squeezeDims = cellfun(@(index) ~strcmp(index, ':') && length(index) == 1, key);
                item = permute(item, [find(~squeezeDims), find(squeezeDims)]); % send empty dimensions to last axes
            end
        end
    end
    
    methods (Access = protected)
        function microns = degreestomicrons(obj, degrees)
            % DEGREESTOMICRONS Convert scan angle degrees to microns using the objective
            % resolution.
            pattern = 'objectiveResolution = (.*)';
            match = regexp(obj.header, pattern, 'tokens', 'dotexceptnewline');
            if ~isempty(match) microns = degrees * str2double(match{1}{1}); end
        end
        
        function rois_ = createrois(obj)
            % CREATEROIS Create scan rois from the configuration file.
            scanimageMetadata = scanreader.utils.gettiffrois(obj.tiffFiles(1));
            roiInfos = scanimageMetadata.RoiGroups.imagingRoiGroup.rois;
            
            roisAsCell = arrayfun(@scanreader.multiroi.ROI, roiInfos, 'uniformOutput', false);
            rois_ = [roisAsCell{:}];
        end
        
        function fields_ = createfields(obj)
            % CREATEFIELDS Go over each slice depth and each roi generating the scanned
            % fields.
            fields_ = [];
            for scanningDepth = obj.scanningDepths
                startingLine = 1;
                for roiId = 1:obj.nRois
                    roi = obj.rois(roiId);
                    newField = roi.getfieldat(scanningDepth);
                    if ~isempty(newField) % if there was a field at that depth
                        if startingLine + newField.height - 1 > obj.pageHeight
                            error('createfields:RuntimeErrror', ['Overestimated number'...
                                'of fly to lines (%d) at scanning depth %d'], ...
                                obj.nFlyToLines, scanningDepth)
                        end
                        
                        % Set xslice and yslice (from where in the page to cut it)
                        newField.ySlices = {startingLine: startingLine + newField.height - 1};
                        newField.xSlices = {1: newField.width};
                        
                        % Set output xslice and yslice (where to paste it in output)
                        newField.outputYSlices = {1: newField.height};
                        newField.outputXSlices = {1: newField.width};
                        
                        % Set roi id
                        newField.roiId = roiId;
                        
                        % Compute next starting y
                        startingLine = startingLine + newField.height + obj.nFlyToLines;
                        
                        % Add field to fields
                        fields_ = [fields_, newField];                      
                    end
                end
            end      
        end
        
        function joincontiguousfields(obj)
            % JOINCONTIGUOUSFIELDS In each scanning depth, join fields that are contiguous.
            %
            % Fields are considered contiguous if they appear next to each other and have 
            % the same size in the touching axis. Process is iterative: it tries to join
            % each field with the remaining ones (checked in order); at the first union it
            % will break and restart the process at the first field. When two fields are
            % joined, it deletes the one appearing last and modifies info such as field
            % height, field width and slices in the one appearing first. 
            % 
            % Any rectangular area in the scan formed by the union of two or more fields 
            % will be treated as a single field after this operation. 
            for scanningDepth = obj.scanningDepths
                twoFieldsWereJoined = true;
                while twoFieldsWereJoined
                    twoFieldsWereJoined = false;
                    
                    fieldsAtDepth = find([obj.fields.depth] == scanningDepth);
                    for j = 1: length(fieldsAtDepth)
                        field1Index = fieldsAtDepth(j);
                        field1 = obj.fields(field1Index);
                        for k = j + 1:length(fieldsAtDepth)
                            field2Index = fieldsAtDepth(k);
                            field2 = obj.fields(field2Index);
                            
                            if field1.iscontiguousto(field2)
                                % Change info in field 1 to reflect the union
                                field1.joinwith(field2)
                                
                                % Delete field 2 in obj.fields
                                obj.fields(field2Index) = [];
                                
                                % Restart join contiguous search
                                twoFieldsWereJoined = true;
                                break % TODOL
                            end
                        end
                        if twoFieldsWereJoined break; end % break again (to get at while)
                    end
                end
            end
        end 
    end
   
end