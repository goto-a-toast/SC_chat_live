// =============================================
// Chat-Controlled Live Performance System
// Phase 1: Keyword-based Controller
// =============================================
// 使い方:
// 1. このファイル全体を選択して Cmd+Enter (Mac) / Ctrl+Enter
// 2. GUIが開く
// 3. テキストボックスにコマンドを入力してEnter
// 4. 音が変わる！
// =============================================

(
s.waitForBoot({

    // =============================================
    // 1. シンセ定義
    // =============================================

    // --- ベースシンセ（常に鳴り続けるドローン的な音） ---
    SynthDef(\chatBass, { arg freq=55, amp=0.3, gate=1, cutoff=800, res=0.3, lfoRate=0.5, lfoDepth=200;
        var sig, env, lfo;
        lfo = SinOsc.kr(lfoRate) * lfoDepth;
        sig = Saw.ar(freq, 0.5) + Pulse.ar(freq * 1.01, 0.4, 0.3);
        sig = MoogFF.ar(sig, (cutoff + lfo).clip(80, 12000), res);
        env = EnvGen.kr(Env.asr(0.5, 1, 2), gate, doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- パッドシンセ ---
    SynthDef(\chatPad, { arg freq=220, amp=0.2, gate=1, cutoff=2000, attack=2, release=3;
        var sig, env;
        sig = Mix.fill(5, { arg i;
            SinOsc.ar(freq * (1 + (i * 0.003)), Rand(0, 2pi)) * 0.2
        });
        sig = sig + (WhiteNoise.ar(0.01));
        sig = LPF.ar(sig, cutoff);
        env = EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- リードシンセ ---
    SynthDef(\chatLead, { arg freq=440, amp=0.15, cutoff=3000, pw=0.5, dur=0.3;
        var sig, env;
        sig = Pulse.ar(freq, pw) + Saw.ar(freq * 0.999);
        sig = RLPF.ar(sig, cutoff, 0.3);
        env = EnvGen.kr(Env.perc(0.01, dur), doneAction: 2);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- キック ---
    SynthDef(\chatKick, { arg amp=0.5;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.01, 0.4), doneAction: 2);
        sig = SinOsc.ar(60 * EnvGen.kr(Env([4, 1], [0.04], [-6]))) * env * amp;
        sig = sig + (WhiteNoise.ar(0.03) * EnvGen.kr(Env.perc(0.001, 0.05)));
        Out.ar(0, sig ! 2);
    }).add;

    // --- ハイハット ---
    SynthDef(\chatHat, { arg amp=0.1, decay=0.08;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.002, decay), doneAction: 2);
        sig = HPF.ar(WhiteNoise.ar, 6000) * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- スネア ---
    SynthDef(\chatSnare, { arg amp=0.3;
        var sig, env;
        env = EnvGen.kr(Env.perc(0.005, 0.2), doneAction: 2);
        sig = (SinOsc.ar(180) * EnvGen.kr(Env.perc(0.001, 0.1))) +
              (HPF.ar(WhiteNoise.ar, 2000) * 0.5);
        sig = sig * env * amp;
        Out.ar(0, sig ! 2);
    }).add;

    // --- FXバス ---
    SynthDef(\chatReverb, { arg mix=0.3, room=0.7;
        var sig;
        sig = In.ar(0, 2);
        sig = FreeVerb2.ar(sig[0], sig[1], mix, room, 0.5);
        ReplaceOut.ar(0, sig);
    }).add;

    SynthDef(\chatDelay, { arg delaytime=0.375, feedback=0.4, mix=0.3;
        var sig, delayed;
        sig = In.ar(0, 2);
        delayed = CombL.ar(sig, 2.0, delaytime, feedback * 4);
        ReplaceOut.ar(0, sig + (delayed * mix));
    }).add;

    s.sync;

    // =============================================
    // 2. 演奏エンジン
    // =============================================

    // --- グローバル状態 ---
    ~state = (
        bpm: 110,
        rootNote: 36,          // C2
        scale: Scale.minor,
        mood: \neutral,
        density: 0.5,
        chaos: 0.0,
        masterVol: 0.7,

        // 各パートのON/OFF
        bassOn: false,
        padOn: false,
        leadOn: false,
        drumOn: false,

        // シンセ参照
        bassSynth: nil,
        padSynth: nil,
        leadSynth: nil,

        // パターン参照
        drumPattern: nil,
        leadPattern: nil,

        // エフェクト
        reverbSynth: nil,
        delaySynth: nil,
        reverbMix: 0.3,
        delayMix: 0.0,

        // --- 各パートの音色パラメータ ---
        // Bass
        bassCutoff: 800,
        bassRes: 0.3,
        bassLfoRate: 0.5,
        bassLfoDepth: 200,
        bassAmp: 0.3,

        // Pad
        padCutoff: 2000,
        padAttack: 2,
        padRelease: 3,
        padAmp: 0.2,

        // Lead
        leadCutoff: 3000,
        leadPw: 0.5,
        leadAmp: 0.15,

        // Drums
        kickAmp: 0.5,
        snareAmp: 0.3,
        hatAmp: 0.1,
        hatDecay: 0.08,
    );

    // --- スケール定義 ---
    ~moodScales = (
        bright:   Scale.major,
        neutral:  Scale.minor,
        dark:     Scale.phrygian,
        chaos:    Scale.chromatic,
        japanese: Scale.ritusen,
        blues:    Scale.new([0, 3, 5, 6, 7, 10], 12),
        arabic:   Scale.new([0, 1, 4, 5, 7, 8, 11], 12),
    );

    // --- ベース開始/停止 ---
    ~startBass = {
        if(~state[\bassSynth].notNil, { ~state[\bassSynth].free });
        ~state[\bassSynth] = Synth(\chatBass, [
            \freq, ~state[\rootNote].midicps,
            \cutoff, ~state[\bassCutoff],
            \res, ~state[\bassRes],
            \lfoRate, ~state[\bassLfoRate],
            \lfoDepth, ~state[\bassLfoDepth],
            \amp, ~state[\bassAmp] * ~state[\masterVol]
        ]);
        ~state[\bassOn] = true;
        ">> Bass ON".postln;
    };

    ~stopBass = {
        if(~state[\bassSynth].notNil, {
            ~state[\bassSynth].set(\gate, 0);
            ~state[\bassSynth] = nil;
        });
        ~state[\bassOn] = false;
        ">> Bass OFF".postln;
    };

    // --- パッド開始/停止 ---
    ~startPad = {
        if(~state[\padSynth].notNil, { ~state[\padSynth].free });
        ~state[\padSynth] = Synth(\chatPad, [
            \freq, (~state[\rootNote] + 12).midicps,
            \cutoff, ~state[\padCutoff],
            \attack, ~state[\padAttack],
            \release, ~state[\padRelease],
            \amp, ~state[\padAmp] * ~state[\masterVol]
        ]);
        ~state[\padOn] = true;
        ">> Pad ON".postln;
    };

    ~stopPad = {
        if(~state[\padSynth].notNil, {
            ~state[\padSynth].set(\gate, 0);
            ~state[\padSynth] = nil;
        });
        ~state[\padOn] = false;
        ">> Pad OFF".postln;
    };

    // --- ドラム開始/停止 ---
    ~startDrums = {
        if(~state[\drumPattern].notNil, { ~state[\drumPattern].stop });
        ~state[\drumPattern] = Routine({
            var stepDur;
            inf.do({ arg i;
                stepDur = 60 / ~state[\bpm] / 2; // 8th notes

                // キック: 4つ打ち + ランダム
                if((i % 4 == 0) or: { ~state[\chaos].coin }, {
                    Synth(\chatKick, [\amp, ~state[\kickAmp] * ~state[\masterVol]]);
                });

                // スネア: 2,4拍
                if(i % 4 == 2, {
                    Synth(\chatSnare, [\amp, ~state[\snareAmp] * ~state[\masterVol]]);
                });

                // ハイハット: density で密度変化
                if(~state[\density].coin, {
                    Synth(\chatHat, [
                        \amp, ~state[\hatAmp] * rrand(0.5, 1.5) * ~state[\masterVol],
                        \decay, ~state[\hatDecay]
                    ]);
                });

                stepDur.wait;
            });
        }).play;
        ~state[\drumOn] = true;
        ">> Drums ON".postln;
    };

    ~stopDrums = {
        if(~state[\drumPattern].notNil, {
            ~state[\drumPattern].stop;
            ~state[\drumPattern] = nil;
        });
        ~state[\drumOn] = false;
        ">> Drums OFF".postln;
    };

    // --- リード開始/停止 ---
    ~startLead = {
        if(~state[\leadPattern].notNil, { ~state[\leadPattern].stop });
        ~state[\leadPattern] = Routine({
            var stepDur, note, degrees;
            inf.do({
                stepDur = 60 / ~state[\bpm];
                degrees = ~state[\scale].degrees;

                // ランダムにスケールの音を選ぶ
                note = ~state[\rootNote] + 24 + degrees.choose;
                if(~state[\chaos] > 0.5, {
                    note = note + rrand(-2, 2); // カオス時は半音ずれる
                });

                if(~state[\density].coin, {
                    var noteDur = stepDur * [0.25, 0.5, 0.5, 1].choose;
                    Synth(\chatLead, [
                        \freq, note.midicps,
                        \amp, ~state[\leadAmp] * ~state[\masterVol],
                        \cutoff, ~state[\leadCutoff] * rrand(0.5, 1.5),
                        \pw, ~state[\leadPw],
                        \dur, noteDur
                    ]);
                    noteDur.wait;
                }, {
                    (stepDur * [0.25, 0.5, 0.5, 1].choose).wait;
                });
            });
        }).play;
        ~state[\leadOn] = true;
        ">> Lead ON".postln;
    };

    ~stopLead = {
        if(~state[\leadPattern].notNil, {
            ~state[\leadPattern].stop;
            ~state[\leadPattern] = nil;
        });
        ~state[\leadOn] = false;
        ">> Lead OFF".postln;
    };

    // --- エフェクト ---
    ~startFX = {
        ~state[\reverbSynth] = Synth.tail(s, \chatReverb, [\mix, ~state[\reverbMix]]);
        ~state[\delaySynth] = Synth.tail(s, \chatDelay, [
            \mix, ~state[\delayMix],
            \delaytime, 60 / ~state[\bpm] / 2
        ]);
        ">> FX chain ready".postln;
    };

    // --- ディレイをBPMに同期 ---
    ~syncDelayToBpm = {
        if(~state[\delaySynth].notNil, {
            ~state[\delaySynth].set(\delaytime, 60 / ~state[\bpm] / 2);
        });
    };

    // =============================================
    // 3. コマンドパーサー（Phase 1 のキモ！）
    // =============================================

    ~parseCommand = { arg input;
        var cmd = input.toLower.stripWhiteSpace;
        var response = "";

        // --- パート ON/OFF ---
        case
        { cmd.contains("bass on") or: { cmd.contains("ベース追加") or: { cmd.contains("bass add") } } } {
            ~startBass.value;
            response = "Bass added to the mix";
        }
        { cmd.contains("bass off") or: { cmd.contains("ベース消") or: { cmd.contains("bass remove") } } } {
            ~stopBass.value;
            response = "Bass removed";
        }
        { cmd.contains("pad on") or: { cmd.contains("パッド追加") or: { cmd.contains("pad add") } } } {
            ~startPad.value;
            response = "Pad layer added";
        }
        { cmd.contains("pad off") or: { cmd.contains("パッド消") or: { cmd.contains("pad remove") } } } {
            ~stopPad.value;
            response = "Pad removed";
        }
        { cmd.contains("drum") and: { cmd.contains("on") or: { cmd.contains("追加") or: { cmd.contains("add") } } } } {
            ~startDrums.value;
            response = "Drums are in!";
        }
        { cmd.contains("drum") and: { cmd.contains("off") or: { cmd.contains("消") or: { cmd.contains("stop") } } } } {
            ~stopDrums.value;
            response = "Drums stopped";
        }
        { cmd.contains("lead") and: { cmd.contains("on") or: { cmd.contains("追加") or: { cmd.contains("add") } } } } {
            ~startLead.value;
            response = "Lead melody started";
        }
        { cmd.contains("lead") and: { cmd.contains("off") or: { cmd.contains("消") or: { cmd.contains("stop") } } } } {
            ~stopLead.value;
            response = "Lead stopped";
        }

        // --- ムード / スケール ---
        { cmd.contains("dark") or: { cmd.contains("ダーク") } } {
            ~state[\mood] = \dark;
            ~state[\scale] = ~moodScales[\dark];
            ~state[\bassCutoff] = 400;
            ~state[\bassRes] = 0.5;
            ~state[\padCutoff] = 800;
            if(~state[\bassSynth].notNil, {
                ~state[\bassSynth].set(\cutoff, 400, \res, 0.5);
            });
            if(~state[\padSynth].notNil, {
                ~state[\padSynth].set(\cutoff, 800);
            });
            ~state[\reverbMix] = 0.6;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.6, \room, 0.9) });
            response = "Going dark... Phrygian scale, deep filter";
        }
        { cmd.contains("bright") or: { cmd.contains("明るく") or: { cmd.contains("happy") } } } {
            ~state[\mood] = \bright;
            ~state[\scale] = ~moodScales[\bright];
            ~state[\bassCutoff] = 2000;
            ~state[\bassRes] = 0.1;
            ~state[\padCutoff] = 4000;
            if(~state[\bassSynth].notNil, {
                ~state[\bassSynth].set(\cutoff, 2000, \res, 0.1);
            });
            if(~state[\padSynth].notNil, {
                ~state[\padSynth].set(\cutoff, 4000);
            });
            ~state[\reverbMix] = 0.2;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.2, \room, 0.4) });
            response = "Bright mode! Major scale, open filter";
        }
        { cmd.contains("blues") or: { cmd.contains("ブルース") } } {
            ~state[\mood] = \blues;
            ~state[\scale] = ~moodScales[\blues];
            response = "Blues scale activated";
        }
        { cmd.contains("japanese") or: { cmd.contains("和風") or: { cmd.contains("日本") } } } {
            ~state[\mood] = \japanese;
            ~state[\scale] = ~moodScales[\japanese];
            response = "Japanese scale (Ritusen)";
        }
        { cmd.contains("arabic") or: { cmd.contains("アラビア") or: { cmd.contains("中東") } } } {
            ~state[\mood] = \arabic;
            ~state[\scale] = ~moodScales[\arabic];
            response = "Arabic scale (Hijaz)";
        }

        // --- テンポ ---
        { cmd.contains("bpm") or: { cmd.contains("tempo") } } {
            var num = cmd.findRegexp("[0-9]+");
            if(num.size > 0, {
                var newBpm = num[0][1].asInteger;
                if((newBpm >= 40) and: { newBpm <= 300 }, {
                    ~state[\bpm] = newBpm;
                    ~syncDelayToBpm.value;
                    response = "Tempo: " ++ newBpm.asString ++ " BPM";
                }, {
                    response = "BPM out of range (40-300)";
                });
            }, {
                response = "Current BPM: " ++ ~state[\bpm].asString;
            });
        }
        { cmd.contains("faster") or: { cmd.contains("速く") or: { cmd.contains("fast") } } } {
            ~state[\bpm] = (~state[\bpm] + 15).min(300);
            ~syncDelayToBpm.value;
            response = "Faster! BPM: " ++ ~state[\bpm].asString;
        }
        { cmd.contains("slower") or: { cmd.contains("遅く") or: { cmd.contains("slow") } } } {
            ~state[\bpm] = (~state[\bpm] - 15).max(40);
            ~syncDelayToBpm.value;
            response = "Slower... BPM: " ++ ~state[\bpm].asString;
        }

        // --- カオス / 密度 ---
        { cmd.contains("chaos") or: { cmd.contains("カオス") or: { cmd.contains("crazy") } } } {
            ~state[\chaos] = (~state[\chaos] + 0.3).min(1.0);
            ~state[\density] = (~state[\density] + 0.2).min(1.0);
            response = "More chaos! Level: " ++ (~state[\chaos] * 100).round.asString ++ "%";
        }
        { cmd.contains("calm") or: { cmd.contains("静か") or: { cmd.contains("chill") } } } {
            ~state[\chaos] = (~state[\chaos] - 0.3).max(0.0);
            ~state[\density] = (~state[\density] - 0.15).max(0.1);
            response = "Calming down... Chaos: " ++ (~state[\chaos] * 100).round.asString ++ "%";
        }
        { cmd.contains("sparse") or: { cmd.contains("スカスカ") } } {
            ~state[\density] = 0.2;
            response = "Sparse mode - density 20%";
        }
        { cmd.contains("dense") or: { cmd.contains("詰めて") or: { cmd.contains("busy") } } } {
            ~state[\density] = 0.9;
            response = "Dense mode - density 90%";
        }

        // --- エフェクト ---
        { cmd.contains("reverb") or: { cmd.contains("リバーブ") or: { cmd.contains("空間") } } } {
            ~state[\reverbMix] = (~state[\reverbMix] + 0.2).min(1.0);
            if(~state[\reverbSynth].notNil, {
                ~state[\reverbSynth].set(\mix, ~state[\reverbMix]);
            });
            response = "Reverb up: " ++ (~state[\reverbMix] * 100).round.asString ++ "%";
        }
        { cmd.contains("delay") or: { cmd.contains("ディレイ") or: { cmd.contains("エコー") } } } {
            ~state[\delayMix] = (~state[\delayMix] + 0.2).min(0.8);
            if(~state[\delaySynth].notNil, {
                ~state[\delaySynth].set(\mix, ~state[\delayMix]);
            });
            response = "Delay up: " ++ (~state[\delayMix] * 100).round.asString ++ "%";
        }
        { cmd.contains("dry") or: { cmd.contains("ドライ") } } {
            ~state[\reverbMix] = 0.05;
            ~state[\delayMix] = 0.0;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.05) });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].set(\mix, 0.0) });
            response = "Dry signal - FX removed";
        }

        // --- フェードアウト ---
        { cmd.contains("fadeout") or: { cmd.contains("フェードアウト") or: { cmd.contains("fade out") } } } {
            response = "Fading out...";
            Routine({
                20.do({ arg i;
                    ~state[\masterVol] = (1.0 - (i / 20)) * 0.7;
                    if(~state[\bassSynth].notNil, {
                        ~state[\bassSynth].set(\amp, ~state[\bassAmp] * ~state[\masterVol]);
                    });
                    if(~state[\padSynth].notNil, {
                        ~state[\padSynth].set(\amp, ~state[\padAmp] * ~state[\masterVol]);
                    });
                    0.15.wait;
                });
                ~stopBass.value;
                ~stopPad.value;
                ~stopDrums.value;
                ~stopLead.value;
                ~state[\masterVol] = 0.7;
                { ~statusText.string_("Faded out. Ready for new commands.") }.defer;
            }).play;
        }

        // --- リセット ---
        { cmd.contains("reset") or: { cmd.contains("リセット") } } {
            ~stopBass.value;
            ~stopPad.value;
            ~stopDrums.value;
            ~stopLead.value;
            ~state[\bpm] = 110;
            ~state[\mood] = \neutral;
            ~state[\scale] = Scale.minor;
            ~state[\chaos] = 0.0;
            ~state[\density] = 0.5;
            ~state[\masterVol] = 0.7;
            ~state[\reverbMix] = 0.3;
            ~state[\delayMix] = 0.0;
            // 音色パラメータもリセット
            ~state[\bassCutoff] = 800;
            ~state[\bassRes] = 0.3;
            ~state[\bassLfoRate] = 0.5;
            ~state[\bassLfoDepth] = 200;
            ~state[\bassAmp] = 0.3;
            ~state[\padCutoff] = 2000;
            ~state[\padAttack] = 2;
            ~state[\padRelease] = 3;
            ~state[\padAmp] = 0.2;
            ~state[\leadCutoff] = 3000;
            ~state[\leadPw] = 0.5;
            ~state[\leadAmp] = 0.15;
            ~state[\kickAmp] = 0.5;
            ~state[\snareAmp] = 0.3;
            ~state[\hatAmp] = 0.1;
            ~state[\hatDecay] = 0.08;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, 0.3, \room, 0.7) });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].set(\mix, 0.0) });
            response = "Reset! All cleared.";
        }

        // --- ヘルプ ---
        { cmd.contains("help") or: { cmd.contains("ヘルプ") } } {
            response = "Commands: bass/pad/lead/drums on|off, dark/bright/blues/japanese/arabic, bpm [num], faster/slower, chaos/calm, reverb/delay/dry, fadeout, reset";
        }

        // --- 未知のコマンド ---
        { true } {
            if(response.size == 0, {
                response = "? Unknown command. Type 'help' for commands.";
            });
        };

        response;
    };

    // =============================================
    // 4. GUI
    // =============================================

    // --- スライダー付きラベル生成ヘルパー ---
    ~makeSlider = { arg parent, bounds, label, min, max, initVal, color, action;
        var labelW = 55, valW = 40, sliderX, sliderW;
        var yPos = bounds.top;
        var xPos = bounds.left;
        var width = bounds.width;
        var valLabel;

        sliderX = xPos + labelW;
        sliderW = width - labelW - valW - 4;

        StaticText(parent, Rect(xPos, yPos, labelW, 16))
            .string_(label)
            .font_(Font("Helvetica", 9))
            .stringColor_(color);

        valLabel = StaticText(parent, Rect(xPos + width - valW, yPos, valW, 16))
            .string_(initVal.round(0.01).asString)
            .font_(Font("Courier", 9))
            .stringColor_(color)
            .align_(\right);

        Slider(parent, Rect(sliderX, yPos, sliderW, 14))
            .background_(Color.gray(0.18))
            .knobColor_(color.alpha_(0.8))
            .value_(initVal.linlin(min, max, 0, 1))
            .action_({ arg sl;
                var val = sl.value.linlin(0, 1, min, max);
                { valLabel.string_(val.round(0.01).asString) }.defer;
                action.value(val);
            });
    };

    {
        var win, inputField, logView, logText;
        var statusColor;
        var toneY, colW, col1, col2, col3, col4;

        // FXチェーン開始
        ~startFX.value;

        // ベースを開始（初期状態）
        ~startBass.value;

        win = Window("Chat Live Controller", Rect(100, 100, 820, 720))
            .background_(Color.gray(0.12));

        // --- タイトル ---
        StaticText(win, Rect(20, 8, 780, 30))
            .string_("Chat Live Performance - Ambient Noise")
            .align_(\center)
            .font_(Font("Helvetica", 18, true))
            .stringColor_(Color.new255(100, 220, 255));

        StaticText(win, Rect(20, 35, 780, 16))
            .string_("Type commands or use tone sliders for real-time control")
            .align_(\center)
            .font_(Font("Helvetica", 10))
            .stringColor_(Color.gray(0.5));

        // --- ステータス表示 ---
        ~statusText = StaticText(win, Rect(20, 56, 780, 20))
            .string_("Ready. Bass is playing.")
            .align_(\center)
            .font_(Font("Helvetica", 11, true))
            .stringColor_(Color.green(0.8));

        // --- パート状態インジケータ ---
        StaticText(win, Rect(20, 80, 780, 16))
            .string_("Active Parts:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        ~partLabels = [\BASS, \PAD, \LEAD, \DRUMS].collect({ arg name, i;
            var label = StaticText(win, Rect(20 + (i * 195), 98, 185, 24))
                .string_(name.asString)
                .align_(\center)
                .font_(Font("Helvetica", 12, true))
                .stringColor_(Color.gray(0.4))
                .background_(Color.gray(0.2));
            label;
        });

        // --- パラメータ表示 ---
        ~paramText = StaticText(win, Rect(20, 128, 780, 36))
            .string_("BPM: 110 | Scale: minor | Chaos: 0% | Density: 50% | Reverb: 30% | Delay: 0% | Mood: neutral")
            .font_(Font("Courier", 10))
            .stringColor_(Color.new255(180, 180, 220));

        // =============================================
        // --- TONE CONTROLS ---
        // =============================================
        toneY = 172;
        colW = 190;
        col1 = 15;
        col2 = col1 + colW + 10;
        col3 = col2 + colW + 10;
        col4 = col3 + colW + 10;

        StaticText(win, Rect(20, toneY - 4, 780, 18))
            .string_("TONE CONTROLS")
            .font_(Font("Helvetica", 11, true))
            .stringColor_(Color.new255(255, 200, 100));

        // ---- BASS ----
        StaticText(win, Rect(col1, toneY + 18, colW, 14))
            .string_("BASS")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.cyan);

        ~makeSlider.value(win, Rect(col1, toneY + 34, colW, 16),
            "Cutoff", 80, 8000, ~state[\bassCutoff], Color.cyan,
            { arg val;
                ~state[\bassCutoff] = val;
                if(~state[\bassSynth].notNil, { ~state[\bassSynth].set(\cutoff, val) });
            });

        ~makeSlider.value(win, Rect(col1, toneY + 54, colW, 16),
            "Reso", 0.0, 1.0, ~state[\bassRes], Color.cyan,
            { arg val;
                ~state[\bassRes] = val;
                if(~state[\bassSynth].notNil, { ~state[\bassSynth].set(\res, val) });
            });

        ~makeSlider.value(win, Rect(col1, toneY + 74, colW, 16),
            "LFO Spd", 0.01, 10.0, ~state[\bassLfoRate], Color.cyan,
            { arg val;
                ~state[\bassLfoRate] = val;
                if(~state[\bassSynth].notNil, { ~state[\bassSynth].set(\lfoRate, val) });
            });

        ~makeSlider.value(win, Rect(col1, toneY + 94, colW, 16),
            "LFO Dpt", 0, 800, ~state[\bassLfoDepth], Color.cyan,
            { arg val;
                ~state[\bassLfoDepth] = val;
                if(~state[\bassSynth].notNil, { ~state[\bassSynth].set(\lfoDepth, val) });
            });

        ~makeSlider.value(win, Rect(col1, toneY + 114, colW, 16),
            "Vol", 0.0, 0.8, ~state[\bassAmp], Color.cyan,
            { arg val;
                ~state[\bassAmp] = val;
                if(~state[\bassSynth].notNil, {
                    ~state[\bassSynth].set(\amp, val * ~state[\masterVol]);
                });
            });

        // ---- PAD ----
        StaticText(win, Rect(col2, toneY + 18, colW, 14))
            .string_("PAD")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.yellow(0.8));

        ~makeSlider.value(win, Rect(col2, toneY + 34, colW, 16),
            "Cutoff", 200, 8000, ~state[\padCutoff], Color.yellow(0.8),
            { arg val;
                ~state[\padCutoff] = val;
                if(~state[\padSynth].notNil, { ~state[\padSynth].set(\cutoff, val) });
            });

        ~makeSlider.value(win, Rect(col2, toneY + 54, colW, 16),
            "Attack", 0.1, 10.0, ~state[\padAttack], Color.yellow(0.8),
            { arg val;
                ~state[\padAttack] = val;
                if(~state[\padSynth].notNil, { ~state[\padSynth].set(\attack, val) });
            });

        ~makeSlider.value(win, Rect(col2, toneY + 74, colW, 16),
            "Release", 0.5, 10.0, ~state[\padRelease], Color.yellow(0.8),
            { arg val;
                ~state[\padRelease] = val;
                if(~state[\padSynth].notNil, { ~state[\padSynth].set(\release, val) });
            });

        ~makeSlider.value(win, Rect(col2, toneY + 94, colW, 16),
            "Vol", 0.0, 0.6, ~state[\padAmp], Color.yellow(0.8),
            { arg val;
                ~state[\padAmp] = val;
                if(~state[\padSynth].notNil, {
                    ~state[\padSynth].set(\amp, val * ~state[\masterVol]);
                });
            });

        // ---- LEAD ----
        StaticText(win, Rect(col3, toneY + 18, colW, 14))
            .string_("LEAD")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.magenta);

        ~makeSlider.value(win, Rect(col3, toneY + 34, colW, 16),
            "Cutoff", 200, 8000, ~state[\leadCutoff], Color.magenta,
            { arg val;
                ~state[\leadCutoff] = val;
                // Lead uses Routine; cutoff applied on next note
            });

        ~makeSlider.value(win, Rect(col3, toneY + 54, colW, 16),
            "PulseW", 0.1, 0.9, ~state[\leadPw], Color.magenta,
            { arg val;
                ~state[\leadPw] = val;
                // Lead uses Routine; pw applied on next note
            });

        ~makeSlider.value(win, Rect(col3, toneY + 74, colW, 16),
            "Vol", 0.0, 0.5, ~state[\leadAmp], Color.magenta,
            { arg val;
                ~state[\leadAmp] = val;
                // Lead uses Routine; amp applied on next note
            });

        // ---- DRUMS ----
        StaticText(win, Rect(col4, toneY + 18, colW, 14))
            .string_("DRUMS")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.green(0.8));

        ~makeSlider.value(win, Rect(col4, toneY + 34, colW, 16),
            "Kick", 0.0, 1.0, ~state[\kickAmp], Color.green(0.8),
            { arg val; ~state[\kickAmp] = val; });

        ~makeSlider.value(win, Rect(col4, toneY + 54, colW, 16),
            "Snare", 0.0, 1.0, ~state[\snareAmp], Color.green(0.8),
            { arg val; ~state[\snareAmp] = val; });

        ~makeSlider.value(win, Rect(col4, toneY + 74, colW, 16),
            "Hat", 0.0, 0.5, ~state[\hatAmp], Color.green(0.8),
            { arg val; ~state[\hatAmp] = val; });

        ~makeSlider.value(win, Rect(col4, toneY + 94, colW, 16),
            "HatDcy", 0.02, 0.5, ~state[\hatDecay], Color.green(0.8),
            { arg val; ~state[\hatDecay] = val; });

        // ---- MASTER / FX ----
        StaticText(win, Rect(20, toneY + 142, 780, 18))
            .string_("MASTER / FX")
            .font_(Font("Helvetica", 11, true))
            .stringColor_(Color.new255(255, 200, 100));

        ~makeSlider.value(win, Rect(col1, toneY + 162, colW, 16),
            "Master", 0.0, 1.0, ~state[\masterVol], Color.white,
            { arg val;
                ~state[\masterVol] = val;
                if(~state[\bassSynth].notNil, {
                    ~state[\bassSynth].set(\amp, ~state[\bassAmp] * val);
                });
                if(~state[\padSynth].notNil, {
                    ~state[\padSynth].set(\amp, ~state[\padAmp] * val);
                });
            });

        ~makeSlider.value(win, Rect(col2, toneY + 162, colW, 16),
            "Reverb", 0.0, 1.0, ~state[\reverbMix], Color.new255(180, 160, 255),
            { arg val;
                ~state[\reverbMix] = val;
                if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\mix, val) });
            });

        ~makeSlider.value(win, Rect(col3, toneY + 162, colW, 16),
            "Delay", 0.0, 0.8, ~state[\delayMix], Color.new255(180, 160, 255),
            { arg val;
                ~state[\delayMix] = val;
                if(~state[\delaySynth].notNil, { ~state[\delaySynth].set(\mix, val) });
            });

        ~makeSlider.value(win, Rect(col4, toneY + 162, colW, 16),
            "Room", 0.0, 1.0, 0.7, Color.new255(180, 160, 255),
            { arg val;
                if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].set(\room, val) });
            });

        // =============================================
        // --- ログ & 入力（下部） ---
        // =============================================

        // --- ログ（コマンド履歴） ---
        StaticText(win, Rect(20, toneY + 190, 780, 16))
            .string_("Command Log:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        logView = ScrollView(win, Rect(20, toneY + 208, 780, 200))
            .background_(Color.gray(0.08))
            .hasBorder_(true);

        logText = StaticText(logView, Rect(5, 5, 760, 2000))
            .string_("")
            .font_(Font("Courier", 10))
            .stringColor_(Color.green(0.7));

        ~logMessages = List[];

        ~addLog = { arg cmd, response;
            var timestamp = Date.getDate.format("%H:%M:%S");
            var displayLines;
            ~logMessages.add("[" ++ timestamp ++ "] > " ++ cmd);
            ~logMessages.add("  " ++ response);
            ~logMessages.add("");

            // 最新の30行だけ表示
            displayLines = if(~logMessages.size > 30, {
                ~logMessages.copyRange(~logMessages.size - 30, ~logMessages.size - 1);
            }, {
                ~logMessages;
            });

            { logText.string_(displayLines.join("\n")) }.defer;
        };

        // --- 状態更新 ---
        ~updateDisplay = {
            var bassColor = if(~state[\bassOn], { Color.cyan }, { Color.gray(0.2) });
            var padColor = if(~state[\padOn], { Color.yellow(0.8) }, { Color.gray(0.2) });
            var leadColor = if(~state[\leadOn], { Color.magenta }, { Color.gray(0.2) });
            var drumColor = if(~state[\drumOn], { Color.green(0.8) }, { Color.gray(0.2) });

            {
                ~partLabels[0].background_(bassColor);
                ~partLabels[1].background_(padColor);
                ~partLabels[2].background_(leadColor);
                ~partLabels[3].background_(drumColor);

                ~partLabels[0].stringColor_(if(~state[\bassOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[1].stringColor_(if(~state[\padOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[2].stringColor_(if(~state[\leadOn], { Color.black }, { Color.gray(0.4) }));
                ~partLabels[3].stringColor_(if(~state[\drumOn], { Color.black }, { Color.gray(0.4) }));

                ~paramText.string_(
                    "BPM: " ++ ~state[\bpm].asString
                    ++ " | Scale: " ++ ~state[\scale].name.asString
                    ++ " | Chaos: " ++ (~state[\chaos] * 100).round.asString ++ "%"
                    ++ " | Density: " ++ (~state[\density] * 100).round.asString ++ "%"
                    ++ " | Reverb: " ++ (~state[\reverbMix] * 100).round.asString ++ "%"
                    ++ " | Delay: " ++ (~state[\delayMix] * 100).round.asString ++ "%"
                    ++ " | Mood: " ++ ~state[\mood].asString
                );
            }.defer;
        };

        // --- テキスト入力 ---
        StaticText(win, Rect(20, toneY + 415, 780, 16))
            .string_("Enter command:")
            .font_(Font("Helvetica", 10, true))
            .stringColor_(Color.gray(0.6));

        inputField = TextField(win, Rect(20, toneY + 433, 780, 30))
            .font_(Font("Courier", 13))
            .background_(Color.gray(0.08))
            .stringColor_(Color.white)
            .action_({ arg field;
                var cmd = field.value;
                var response;

                if(cmd.size > 0, {
                    response = ~parseCommand.value(cmd);
                    ~addLog.value(cmd, response);
                    ~statusText.string_(response);
                    ~updateDisplay.value;
                    field.string_("");
                });
            });

        win.onClose_({
            ~stopBass.value;
            ~stopPad.value;
            ~stopDrums.value;
            ~stopLead.value;
            if(~state[\reverbSynth].notNil, { ~state[\reverbSynth].free });
            if(~state[\delaySynth].notNil, { ~state[\delaySynth].free });
            "Chat Live Controller closed.".postln;
        });

        win.front;
        inputField.focus;

        ~updateDisplay.value;
        "=============================================".postln;
        "  Chat Live Performance System - Phase 1    ".postln;
        "  Tone Controls + Chat Commands             ".postln;
        "  Type 'help' for available commands         ".postln;
        "=============================================".postln;

    }.defer;

});
)
