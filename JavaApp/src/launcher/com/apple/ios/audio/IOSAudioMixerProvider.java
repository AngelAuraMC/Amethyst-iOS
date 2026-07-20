package com.apple.ios.audio;

import javax.sound.sampled.Mixer;
import javax.sound.sampled.spi.MixerProvider;

public class IOSAudioMixerProvider extends MixerProvider {

    private final IOSAudioMixer mixer = new IOSAudioMixer();

    @Override
    public Mixer.Info[] getMixerInfo() {
        return new Mixer.Info[]{mixer.getMixerInfo()};
    }

    @Override
    public Mixer getMixer(Mixer.Info info) {
        if (info.equals(mixer.getMixerInfo())) {
            return mixer;
        }
        throw new IllegalArgumentException("Unknown mixer: " + info);
    }
}
