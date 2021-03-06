classdef FilterDesignerTests < matlab.unittest.TestCase
    % Test ad936x Filter Designer
    %
    % This testing utilizes the provided 'ad9361_settings.mat' file to
    % generate test input vectors which are permuted to exercise additional
    % functionality of the designer.
    %
    % Currently these tests compare results of the generated (MEX/DLL) with
    % the existing implementation of the filter designer. The following
    % fields are compared:
    % - firtaps
    %
    % The DLL generated code is tested through an opaque call from a MEX
    % function allowing direct access to the DLL outputs in MATLAB
    %
    % Example call:
    %  test = FilterDesignerTests;
    %  test.run()
    
    properties
        args = '{Rdata, Fpass,Fstop,caldiv,FIR,HB1,PLL_mult,Apass,Astop,phEQ,HB2,HB3,Type,RxTx,RFbw,DAC_div,converter_rate,PLL_rate,Fcenter,wnom,FIRdBmin,int_FIR}';
        args2 = '{input.Rdata, input.Fpass, input.Fstop, input.caldiv, input.FIR, input.HB1, input.PLL_mult, input.Apass, input.Astop, input.phEQ, input.HB2, input.HB3, input.Type, input.RxTx, input.RFbw, input.DAC_div, input.converter_rate, input.PLL_rate, input.Fcenter, input.wnom, input.FIRdBmin, input.int_FIR}';
        functionName = 'internal_design_filter_cg';
        passedCodegenMEX = false;
        passedCodegenDLL = false;
        settingsLoaded = false;
        ad9361_settings = [];
    end
    
    methods(TestClassSetup)
        % Load example settings from mat file
        function loadTemplateSettings(testCase)
            a = load('ad9361_settings.mat');
            testCase.ad9361_settings = a.ad9361_settings;
            testCase.settingsLoaded = true;
        end
        % Test Codegen of MEX Target
        function testCodegenBuildMEX(testCase)
            %% Setup workspace
            % Get example struct
            inputVar = testCase.ad9361_settings.tx.LTE5;
            % Fill out necessary fields
            input = process_input(inputVar); %#ok<NASGU>
            %% Call codegen
            %cfg = coder.config('mex','ecoder',true);
            cfg = coder.config('mex');
            cfg.TargetLang='C++';
            result = codegen('-config','cfg',testCase.functionName,'-args',testCase.args2);
            testCase.passedCodegenMEX = result.summary.passed;
            testCase.verifyTrue(result.summary.passed);
        end
        % Test Codegen of DLL Target
        function testCodegenBuildDLL(testCase)
            %% Setup workspace
            % Get example struct
            inputVar = testCase.ad9361_settings.tx.LTE5;
            % Fill out necessary fields
            input = process_input(inputVar); %#ok<NASGU>
            %% Call codegen
            %cfg = coder.config('dll','ecoder',true);
            cfg = coder.config('dll');
            cfg.TargetLang='C++';
            cfg.FilePartitionMethod='SingleFile';
            result = codegen('-config','cfg',testCase.functionName,'-O ','disable:openmp','-args',testCase.args2);
            testCase.passedCodegenDLL = result.summary.passed;
            testCase.verifyTrue(result.summary.passed);
            if testCase.passedCodegenDLL && ismac % Move library to root (rpath is buggy on mac)
                !mv codegen/dll/internal_design_filter_cg/internal_design_filter_cg.dylib .
            end
        end
        % Create MAT file for generated tests and generate tests
        function GenTesMATtFiles(testCase)
            if ~testCase.passedCodegenDLL || ~testCase.settingsLoaded
                error('Must generate code first and load settings');
            end
            filename = 'ad9361_settings_processed_test';
            
            %% RX
            in = testCase.ad9361_settings.rx.LTE5;
            % Generate template expected results
            input = testCase.input_cooker(in);
            refResult = internal_design_filter(input); % reference
            firtaps = refResult.firtaps; %#ok<NASGU>
            % Save to file
            save(filename, 'firtaps', 'input');
            % Generate TestCase
            cfg = coder.config('mex');
            cfg.TargetLang='C++';
            if ismac
                cfg.CustomLibrary = [testCase.functionName,'.dylib'];
            elseif isunix
                cfg.CustomLibrary = [testCase.functionName,'.so'];
            else
                cfg.CustomLibrary = [testCase.functionName,'.dll'];
            end
            additionalSource = {[testCase.functionName,'.h']};
            cfg.CustomInclude = ['codegen/dll/',testCase.functionName,'/'];
            result = codegen('-config','cfg','TestToBeGenerated',...
                additionalSource{:},'-o','TestToBeGenerated_rx_mex');
            testCase.verifyTrue(result.summary.passed);
            %% TX
            in = testCase.ad9361_settings.tx.LTE5;
            % Generate template expected results
            input = testCase.input_cooker(in);
            refResult = internal_design_filter(input); % reference
            firtaps = refResult.firtaps; %#ok<NASGU>
            % Save to file
            save(filename, 'firtaps', 'input');
            % Generate TestCase
            cfg = coder.config('mex');
            cfg.TargetLang='C++';
            if ismac
                cfg.CustomLibrary = [testCase.functionName,'.dylib'];
            elseif isunix
                cfg.CustomLibrary = [testCase.functionName,'.so'];
            else
                cfg.CustomLibrary = [testCase.functionName,'.dll'];
            end
            additionalSource = {[testCase.functionName,'.h']};
            cfg.CustomInclude = ['codegen/dll/',testCase.functionName,'/'];
            result = codegen('-config','cfg','TestToBeGenerated',...
                additionalSource{:},'-o','TestToBeGenerated_tx_mex');
            testCase.verifyTrue(result.summary.passed);
        end
        
        
    end
    
%     methods(TestClassTeardown)
%         function removeCodegenFiles(testCase)
%             % Remove generated code
%             [~,~,~] = rmdir('codegen','s');
%             if ismac
%                 delete([testCase.functionName,'.dylib']);
%             end
%             delete('TestToBeGenerated_tx_mex.*')
%             delete('TestToBeGenerated_rx_mex.*')
%         end
%     end
    
    methods (Static)
        
        % Build input so all fields are filled
        function input = input_cooker(input)
            % support a simple data rate input otherwise it must be a structure
            if isfloat(input)
                input = struct('Rdata', input);
            end
            input = cook_input(input);
            
            % use the internal FIR if unspecified
            if ~isfield(input, 'int_FIR')
                input.int_FIR = 1;
            end
            
            % nominal frequency can't be zero
            if ~input.wnom
                input.wnom = (input.PLL_rate/input.caldiv)*(log(2)/(2*pi));
            end
        end
        
        % Modify input based on additional configuration
        function input = modifyInput(input,config)
            cFields = fields(config);
            for field = 1:length(cFields)
                if strcmp(cFields{field},'txrx')
                    continue;
                end
                input = setfield(input, cFields{field}, getfield(config,cFields{field})); %#ok<SFLD,GFLD>
            end
        end
        
        % Pass code to raspberry pi
        function runOnPi()
            
        end
        
    end
    
    methods % Non-Static Test Scaffolding
        
        
        function testFunctionGeneral(testCase,config)
            if ~testCase.passedCodegenMEX || ~testCase.settingsLoaded
                error('Must generate code first and load settings');
            end
            % Get settings
            if strcmp(config.txrx,'tx')
                txrx = testCase.ad9361_settings.tx;
            else
                txrx = testCase.ad9361_settings.rx;
            end
            frt = fields(txrx);
            % Test all configurations LTE5-20
            for s = 1:length(fields(txrx))
                % Build input
                str = char(frt{s});
                in = getfield(txrx,str); %#ok<GFLD>
                input = testCase.input_cooker(in);
                % Update settings based on config
                input = testCase.modifyInput(input,config);
                % Test
                cgResultFirtaps = call_filter_designer_cg(input,true); % codegen mex
                refResult = internal_design_filter(input); % reference
                % Evaluate errors
                testCase.verifyEqual(cgResultFirtaps,refResult.firtaps);
            end
            
        end
        function testFunctionGeneralLengthCheck(testCase,config)
            if ~testCase.passedCodegenMEX || ~testCase.settingsLoaded
                error('Must generate code first and load settings');
            end
            % Get settings
            if strcmp(config.txrx,'tx')
                txrx = testCase.ad9361_settings.tx;
            else
                txrx = testCase.ad9361_settings.rx;
            end
            frt = fields(txrx);
            % Test all configurations LTE5-20
            for s = 1:length(fields(txrx))
                % Build input
                str = char(frt{s});
                in = getfield(txrx,str); %#ok<GFLD>
                input = testCase.input_cooker(in);
                % Update settings based on config
                input = testCase.modifyInput(input,config);
                % Test
                cgResultFirtaps = call_filter_designer_cg(input,true); % codegen mex
                refResult = internal_design_filter(input); % reference
                % Evaluate errors
                testCase.verifyEqual(length(cgResultFirtaps),length(refResult.firtaps));
                testCase.verifyEqual(cgResultFirtaps,refResult.firtaps,'AbsTol',3);
            end
            
        end
        
        function testGeneratedFunctionGeneral(testCase,config)
            if ~testCase.passedCodegenMEX || ~testCase.settingsLoaded
                error('Must generate code first and load settings');
            end
            % Get settings
            if strcmp(config.txrx,'tx')
                txrx = testCase.ad9361_settings.tx;
            else
                txrx = testCase.ad9361_settings.rx;
            end
            frt = fields(txrx);
            % Test all configurations LTE5-20
            for s = 1:length(fields(txrx))
                % Build input
                str = char(frt{s});
                in = getfield(txrx,str); %#ok<GFLD>
                input = testCase.input_cooker(in);
                % Update settings based on config
                input = testCase.modifyInput(input,config);
                % Save test data to file
                filename = 'ad9361_settings_processed_test';
                refResult = internal_design_filter(input); % reference
                firtaps = refResult.firtaps; %#ok<NASGU>
                % Save to file
                save(filename, 'firtaps', 'input');
                % Test
                if strcmp(config.txrx,'tx')
                    firtaps = TestToBeGenerated_tx_mex();
                else
                    firtaps = TestToBeGenerated_rx_mex();
                end
                testCase.verifyEqual(firtaps,refResult.firtaps);
            end
            
        end
        
    end
    
    methods (Test)
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Tests
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        %%%% RX
        
        % Test MEX results with standard setting
        function testRXMEX(testCase)
            config = struct;
            config.txrx = 'rx';
            testCase.testFunctionGeneral(config);
        end
        % Test MEX results with reference without EQ
        function testRXEQMEX(testCase)
            config = struct;
            config.txrx = 'rx';
            config.phEQ = 1;
            testCase.testFunctionGeneral(config);
        end
        % Test MEX results with reference without EQ
        function testRXNonStandardFIRMEX(testCase)
            config = struct;
            config.txrx = 'rx';
            config.int_FIR = 0;
            testCase.testFunctionGeneralLengthCheck(config);
        end
        % Test DLL results with standard setting
        function testRXDLL(testCase)
            config = struct;
            config.txrx = 'rx';
            testCase.testGeneratedFunctionGeneral(config);
        end
        
        %%%% TX
        
        % Test MEX results with reference without EQ
        function testTXMEX(testCase)
            config = struct;
            config.txrx = 'tx';
            testCase.testFunctionGeneral(config);
        end
        % Test MEX results with reference without EQ
        function testTXEQMEX(testCase)
            config = struct;
            config.txrx = 'tx';
            config.phEQ = 1;
            testCase.testFunctionGeneral(config);
        end
        % Test MEX results with reference without EQ
        function testTXNonStandardFIRMEX(testCase)
            config = struct;
            config.txrx = 'tx';
            config.int_FIR = 0;
            testCase.testFunctionGeneralLengthCheck(config);
        end
        % Test DLL results with standard setting
        function testTXDLL(testCase)
            config = struct;
            config.txrx = 'tx';
            testCase.testGeneratedFunctionGeneral(config);
        end
    end
    
end