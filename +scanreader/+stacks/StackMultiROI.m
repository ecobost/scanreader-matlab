classdef StackMultiROI < scanreader.scans.ScanMultiROI & scanreader.stacks.BaseStack
    methods
        function obj = StackMultiROI(joinContiguous)
            % make sure the right constructor is called
            obj@scanreader.scans.ScanMultiROI(joinContiguous)
        end
    end
end