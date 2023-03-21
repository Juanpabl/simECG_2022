function [simECGdata, initialParameters, annotations] = simECG_generator(sigLength, realRRon, realVAon, realAAon, noiseType, noiseRMS, onlyRR, arrhythmiaParameters, simECGdata)
% [] = simECG_generator() returns a 15-by-N matrix containing 15 lead
% ECGs. Three types of ECG signals can be generated: SR (AF burden set to 0, 
% AF (AF burden set to 1) or PAF (AF burden any value from the interval 
% (0, 1)). Standard leads I, II, III, aVR, aVL, aVF, V1, V2, V3, V4, V5, V6
% and Frank leads X, Y, Z are generated(sampling frequence 1000 Hz).
%
% Generated leads:
% multileadVA(1,:) - I      multileadVA(7,:) - V1    multileadVA(13,:) - X     
% multileadVA(2,:) - II     multileadVA(8,:) - V2    multileadVA(14,:) - Y  
% multileadVA(3,:) - III    multileadVA(9,:) - V3    multileadVA(15,:) - Z  
% multileadVA(4,:) - aVR    multileadVA(10,:) - V4 
% multileadVA(5,:) - aVL    multileadVA(11,:) - V5 
% multileadVA(6,:) - aVF    multileadVA(12,:) - V6 
%
% Input arguments:
% rrLength indicates the length of the desired ECG signal (in RR intervals)
%
% realRRon 1 indicates that real RR intervals are used, 0 - synthetic
% realVAon 1 indicates that real ventricular activity is used, 0 - synthetic
% realAAon 1 indicates that real atrial activity is used, 0 - synthetic
%
% onlyRR 1 - only RR intervals are generated, 0 - multilead ECG is generated
%
% noiseType: a number from 0 to 4
% 0 - no noise added (noise RMS = 0 mV)
% 1 - motion artefacts
% 2 - electrode movement artefacts
% 3 - baseline wander
% 4 - mixture of type 1, type 2 and type 3 noises
%
% noiseLevel - noise level in milivolts, i.e. 0.02 corresponds to 20 uV
%
% arrhythmiaParameters is a structure containing the following fields:
% - AFburden is a value between 0 and 1. 0: the entire signal is SR, 
% 1: the entire signal is AF.
% - stayInAF denotes the probability to stay in AF
%
% Output arguments:
% simECGdata returns generated data (multilead ECG, multilead ventricular
% activity, multilead atrial activity, QRS index, etc.). initialParameters 
% returns initial parameter values used to generated ECG signals.   
%
% Known problems:
% AV node model used for generating RR intervals during AF is relatively slow.
%
% Synthetic P wave amplitude is nearly 1.5 lower in several leads than that
% observed in reality (at least for healthy patients). Parameters for 
% simulating Type 2 P waves are taken from the paper by Havmoller et al. 
% Age-related changes in P wave morphology in healthy subjects. 
% BMC Cardiovascular Disorders, 7(1), 22, 2007.
%
% Interpolated TQ intervals (using a cubic spline interpolation) sometimes 
% do not look realistic.

disp('    ECG generator: simulation starting ...');

if simECGdata.MA_Prob > 1, simECGdata.MA_Prob = 1 / simECGdata.MA_Prob; end

switch onlyRR
    case 1 % only RR intervals are generated
        % Generate initial parameters (fibrillatory frequency)
        fibFreqz = simECG_fibrillation_frequency();
        % Generate RR intervals
        [rr,annotations,targets_beats,simECGdata,hrArray,state_history] = simECG_global_rr_intervals(sigLength, fibFreqz, realRRon, arrhythmiaParameters, simECGdata);
        rr(cumsum(rr)>sigLength)= [];
        rrLength = numel(rr);
        simECGdata.rr = rr;
        simECGdata.multileadECG = [];
        simECGdata.multileadVA = [];
        simECGdata.multileadAA = [];
        simECGdata.multileadNoise = [];
        simECGdata.QRSindex = [];
        simECGdata.targets_beats = targets_beats;
        simECGdata.ecgLength = sigLength;
        simECGdata.Fr = [];
        simECGdata.poles = [];
        simECGdata.state_history = state_history;
        simECGdata.hrArray = hrArray;
        
        initialParameters.fibFreqz = fibFreqz;
        initialParameters.rrLength = rrLength;
        initialParameters.realRRon = realRRon;
        initialParameters.realVAon = realVAon;
        initialParameters.realVAon = realAAon;
        initialParameters.noiseType = noiseType;
        initialParameters.noiseRMS = noiseRMS;
        
    case 0 % multilead ECG is generated
        % Check for errors:
        if (realVAon == 0) && (realAAon == 1)
            msg = ('Selection of synthetic ventricular activity and real atrial activity is not allowed');
            error('MyComponent:incorrectType', msg);
        end

        % Generate initial parameters (fibrillatory frequency)
        fibFreqz = simECG_fibrillation_frequency();   
        % Generate RR intervals
        [rrIn,annotations,targets_beats,simECGdata,hrArray,state_history] = simECG_global_rr_intervals(sigLength,fibFreqz, realRRon, arrhythmiaParameters, simECGdata);
        rrLength = numel(rrIn);
        % Generate multilead ventricular activity
        [QRSindex, TendIndex,rr, multileadVA, ecgLength] = simECG_generate_multilead_VA(rrLength, targets_beats, rrIn, realVAon, simECGdata,state_history); %_QTC adde by Alba 19/03
        simECGdata.rr = rr./simECGdata.fs;
        % Generate multilead atrial activity
        multileadAA = simECG_generate_multilead_AA(targets_beats, QRSindex, fibFreqz, realAAon, ecgLength, arrhythmiaParameters.B_af, simECGdata);
        % Generate multilead noise
        for ii = 1:numel(noiseType)
            [multileadNoise_All(:,:,ii)] = simECG_generate_noise(ecgLength, noiseType(ii), noiseRMS(ii), simECGdata, multileadVA);
        end
        multileadNoise = sum(multileadNoise_All,3);
        % Generate multilead noise
        multileadECG = multileadVA + multileadAA + multileadNoise;

        simECGdata.rr = rr;
        simECGdata.multileadECG = multileadECG;
        simECGdata.multileadVA = multileadVA;
        simECGdata.multileadAA = multileadAA;
        simECGdata.multileadNoise = multileadNoise;
        simECGdata.multileadNoise_All = multileadNoise_All;
        simECGdata.QRSindex = QRSindex;
        simECGdata.TendIndex = TendIndex;
        simECGdata.targets_beats = targets_beats;
        simECGdata.state_history = state_history;
        simECGdata.ecgLength = ecgLength';
        simECGdata.Fr = simECGdata.Fr';
        simECGdata.state_history = state_history;
        simECGdata.hrArray = hrArray;
        
        initialParameters.fibFreqz = fibFreqz;
        initialParameters.rrLength = rrLength;
        initialParameters.realRRon = realRRon;
        initialParameters.realVAon = realVAon;
        initialParameters.realVAon = realAAon;
        initialParameters.noiseType = noiseType;
        initialParameters.noiseRMS = noiseRMS;
        
end

end