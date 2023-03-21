function multileadAA = simECG_generate_multilead_AA(targets_beats, QRSindex, fibFreqz, realAAon, ecgLength, B_af, simECGdata)
% multileadAA = simECG_gen_multilead_AA() returns multilead (15 lead) atrial
% activity. 
%
% Generated leads:
% multileadAA(1,:) - I      multileadAA(7,:) - V1    multileadAA(13,:) - X     
% multileadAA(2,:) - II     multileadAA(8,:) - V2    multileadAA(14,:) - Y  
% multileadAA(3,:) - III    multileadAA(9,:) - V3    multileadAA(15,:) - Z  
% multileadAA(4,:) - aVR    multileadAA(10,:) - V4 
% multileadAA(5,:) - aVL    multileadAA(11,:) - V5 
% multileadAA(6,:) - aVF    multileadAA(12,:) - V6 

%Last update: CPerez 05/2022

% Decide which rhythm type to generate
if B_af == 0
    rhythmType = 0; % SR
elseif B_af == 1
    rhythmType = 1; % AF
elseif B_af > 0 && B_af < 1
    rhythmType = 2; % PAF
else
    error('AF burden must be a value between 0 and 1')
end

disp('Generating atrial activity ...');

% P wave parameter norm threshold which ensured that APBs have a different
% enough P wave
params_th = 6;
multileadAA = zeros(15, ecgLength);
% Generate atrial activity
switch rhythmType
    case 0 % Entire signal is SR
       if realAAon == 0
           Nrr = length(targets_beats);
           [P_waves, ~] = simECG_generate_multilead_P_waves(Nrr); 
           template_S = squeeze(P_waves([1,2,7,8,9,10,11,12],1,:));
           
           % Replace P waves during atrial ectopic beats
           numABPs = length(find(targets_beats == 3));
           if numABPs > 0
               tot_corr = params_th;
               while tot_corr>=params_th
                   tot_corr = 0;
                   [P_waves_APBs, ~] = simECG_generate_multilead_P_waves(numABPs);
                   template_APB = squeeze(P_waves_APBs([1,2,7,8,9,10,11,12],1,:));
                   for l = 1:8
                       m = corrcoef(template_S(l,:),template_APB(l,:));
                       tot_corr = tot_corr + abs(m(1,2));
                   end
               end
               iAPB = 1;
               for n = 1:Nrr 
                   if targets_beats(n) == 3
                       P_waves(:,n,:) = P_waves_APBs(:,iAPB,:);
                       iAPB = iAPB + 1;
                   end
               end
           end
           
           % Insert P waves% CPerez 03/2022
           Fs = 1000; 
           RR = diff(QRSindex./Fs); %seconds
           QR = 50;
           for p_num = 2:Nrr
               % avoid placing P waves for ventricular beats %Lorenzo
               if targets_beats(p_num) ~= 4
                   bias = 0;
                   if ~isfield(simECGdata,'peak') || (QRSindex(p_num) <= simECGdata.peak*1e3) %Exercise or normal
                       if RR(p_num-1) < 0.520 %Change point
                           PQ = round(152 + 358*(RR(p_num-1)-0.520));%-34.53 + 361.21*RR
                       else
                           PQ = randi([140 160],1); %constant 152
                       end
                   end
                   
                   if isfield(simECGdata,'peak') && QRSindex(p_num) > simECGdata.peak*1e3 %Recovery
                       if RR(p_num-1) < 0.430 %Change point
                           PQ = round(-65 + 470*RR(p_num-1)); %-65.26 + 470.24*RR
                       else
                           PQ = randi([130 150],1); %constant 139
                       end
                   end
                   
                   lenP = length(QRSindex(p_num)-(PQ + QR -1):QRSindex(p_num)-QR);
                   bias = lenP - size(P_waves,3);
                   if bias < 0
                       multileadAA(:, QRSindex(p_num)-(PQ + QR -1 -bias):QRSindex(p_num)- QR) = P_waves(:,p_num,:);
                   else
                       multileadAA(:, QRSindex(p_num)-(PQ + QR -1):QRSindex(p_num)- (QR + bias)) = P_waves(:,p_num,:);
                   end
                   %                else
                   %                    multileadAA(:, QRSindex(p_num)-249:QRSindex(p_num)-100) = P_waves(:,p_num,:);
                   %                end
               end
           end
       end   
       
       
       
    case 1 % Entire signal is AF
        if realAAon == 0
            multileadAA = simECG_generate_multilead_f_waves(fibFreqz, ecgLength);
        else
            sigNum = randi([1 20]);
            load('DATA_f_waves_real')
            f_waves = DATAfWaves(sigNum).f_waves;
            
            clear DATA_f_waves_real
            
            if ecgLength > length(f_waves)   % Concatenate if RR series is shorter than the desired length
                nCycles = ceil(ecgLength/length(f_waves));
                multileadAA = [];
                for i = 1:nCycles
                    multileadAA = [multileadAA f_waves];
                end
                multileadAA = multileadAA(:,1:ecgLength);  
            else
                fStart = randi([1 (length(f_waves)-ecgLength)]); % Randomly select start position
                multileadAA = f_waves(:,fStart+1:fStart+ecgLength);
            end   
        end
                
    case 2 % PAF
        Nrr = length(targets_beats);
        if realAAon == 0  % Synthetic atrial activity is prefered
           [P_waves, ~] = simECG_generate_multilead_P_waves(Nrr); 
           template_S = squeeze(P_waves([1,2,7,8,9,10,11,12],1,:));
           
           % Replace P waves during atrial ectopic beats
           numABPs = length(find(targets_beats == 3));
           if numABPs > 0
               tot_corr = params_th;
               while tot_corr>=params_th
                   tot_corr = 0;
                   [P_waves_APBs, ~] = simECG_generate_multilead_P_waves(numABPs);
                   template_APB = squeeze(P_waves_APBs([1,2,7,8,9,10,11,12],1,:));
                   for l = 1:8
                       m = corrcoef(template_S(l,:),template_APB(l,:));
                       tot_corr = tot_corr + abs(m(1,2));
                   end
               end
               iAPB = 1;
               for n = 1:Nrr 
                   if targets_beats(n) == 3
                       P_waves(:,n,:) = P_waves_APBs(:,iAPB,:);
                       iAPB = iAPB + 1;
                   end
               end
           end
           % Insert P waves% CPerez 03/2022
           Fs = 1000; 
           RR = diff(QRSindex./Fs); %seconds
           QR = 50;
           % Insert P waves
           for p_num = 2:Nrr
               % avoid placing P waves for ventricular beats %Lorenzo
               if targets_beats(p_num) ~= 4
                   bias = 0;
                   if ~isfield(simECGdata,'peak') || (QRSindex(p_num) <= simECGdata.peak*1e3) %Exercise or normal
                       if RR(p_num-1) < 0.520 %Change point
                           PQ = round(152 + 358*(RR(p_num-1)-0.520));%-34.53 + 361.21*RR
                       else
                           PQ = randi([140 160],1); %constant 152
                       end
                   end
                   
                   if isfield(simECGdata,'peak') && QRSindex(p_num) > simECGdata.peak*1e3 %Recovery
                       if RR(p_num-1) < 0.430 %Change point
                           PQ = round(-65 + 470*RR(p_num-1)); %-65.26 + 470.24*RR
                       else
                           PQ = randi([130 150],1); %constant 139
                       end
                   end
                   
                   lenP = length(QRSindex(p_num)-(PQ + QR -1):QRSindex(p_num)-QR);
                   bias = lenP - size(P_waves,3);
                   if bias < 0
                       multileadAA(:, QRSindex(p_num)-(PQ + QR -1 -bias):QRSindex(p_num)- QR) = P_waves(:,p_num,:);
                   else
                       multileadAA(:, QRSindex(p_num)-(PQ + QR -1):QRSindex(p_num)- (QR + bias)) = P_waves(:,p_num,:);
                   end
                   %                else
                   %                    multileadAA(:, QRSindex(p_num)-249:QRSindex(p_num)-100) = P_waves(:,p_num,:);
                   %                end
               end
           end
           % Generate f waves
           f_waves = simECG_generate_multilead_f_waves(fibFreqz, ecgLength);
           % Insert f waves
           for p_num = 2:Nrr
               if (targets_beats(p_num) == 2) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num-1) == 2))
                   praIndex = QRSindex(p_num);
                   while ( (targets_beats(p_num) == 2) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num-1) == 2)) ) ...
                       && ( p_num < Nrr )
                      p_num = p_num + 1;
                   end 
                   pabIndex = QRSindex(p_num);
                   multileadAA(:, praIndex:pabIndex) = f_waves(:,praIndex:pabIndex);   
               end
           end
               
        else % Real atrial activity is prefered
            sigNum = randi([1 20]);
            load('DATA_f_waves_real')
            f_waves = DATAfWaves(sigNum).f_waves;
            
            clear DATA_f_waves_real
            
            if ecgLength > length(f_waves)   % Concatenate if RR series is shorter than the desired length
                nCycles = ceil(ecgLength/length(f_waves));
                multileadfWaves = [];
                for i = 1:nCycles
                    multileadfWaves = [multileadfWaves f_waves];
                end
                multileadfWaves = multileadfWaves(:,1:ecgLength);  
            else
                fStart = randi([1 (length(f_waves)-ecgLength)]); % Randomly select start position
                multileadfWaves = f_waves(:,fStart+1:fStart+ecgLength);
            end 
            for p_num = 2:Nrr
                if (targets_beats(p_num) == 2) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num-1) == 2)) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num+1) == 2))
                    praIndex = QRSindex(p_num);
                    while ( (targets_beats(p_num) == 2) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num-1) == 2)) ||...
                       ((targets_beats(p_num) == 4)&&(targets_beats(p_num+1) == 2)) ) && ( p_num < Nrr )
                        p_num = p_num + 1;
                    end 
                    if p_num>length(QRSindex)
                        temp=1;
                    end
                    pabIndex = QRSindex(p_num);
                    multileadAA(:, praIndex:pabIndex) = multileadfWaves(:,praIndex:pabIndex);
                end
            end
            
        end
             
end

