package com.apple.ios.audio;

import javax.sound.sampled.*;

public class IOSAudioMixer implements Mixer {

    private static class IOSMixerInfo extends Mixer.Info {
        IOSMixerInfo() {
            super("iOS Audio Capture", "Amethyst",
                  "iOS native microphone via AVAudioEngine", "1.0");
        }
    }

    private static final Mixer.Info INFO = new IOSMixerInfo();

    private final IOSTargetDataLine targetLine;

    public IOSAudioMixer() {
        targetLine = new IOSTargetDataLine();
    }

    @Override
    public Info getMixerInfo() {
        return INFO;
    }

    @Override
    public Line[] getSourceLines() {
        return new Line[0];
    }

    @Override
    public Line[] getTargetLines() {
        return new Line[]{targetLine};
    }

    @Override
    public Line.Info[] getSourceLineInfo() {
        return new Line.Info[0];
    }

    @Override
    public Line.Info[] getTargetLineInfo() {
        return new Line.Info[]{new DataLine.Info(TargetDataLine.class, null, AudioSystem.NOT_SPECIFIED)};
    }

    @Override
    public Line.Info[] getSourceLineInfo(Line.Info info) {
        return new Line.Info[0];
    }

    @Override
    public Line.Info[] getTargetLineInfo(Line.Info info) {
        if (info instanceof DataLine.Info) {
            Class<?> lineClass = ((DataLine.Info) info).getLineClass();
            if (lineClass == TargetDataLine.class || lineClass == Line.class) {
                return new Line.Info[]{new DataLine.Info(TargetDataLine.class, null, AudioSystem.NOT_SPECIFIED)};
            }
        }
        return new Line.Info[0];
    }

    @Override
    public boolean isLineSupported(Line.Info info) {
        if (info instanceof DataLine.Info) {
            Class<?> lineClass = ((DataLine.Info) info).getLineClass();
            return lineClass == TargetDataLine.class || lineClass == Line.class;
        }
        return false;
    }

    @Override
    public Line getLine(Line.Info info) throws LineUnavailableException {
        if (info instanceof DataLine.Info) {
            Class<?> lineClass = ((DataLine.Info) info).getLineClass();
            if (lineClass == TargetDataLine.class || lineClass == Line.class) {
                return targetLine;
            }
        }
        throw new IllegalArgumentException("Unsupported line: " + info);
    }

    @Override
    public int getMaxLines(Line.Info info) {
        if (info instanceof DataLine.Info) {
            Class<?> lineClass = ((DataLine.Info) info).getLineClass();
            if (lineClass == TargetDataLine.class || lineClass == Line.class) {
                return 1;
            }
        }
        return 0;
    }

    @Override
    public void open() {
    }

    @Override
    public void close() {
        targetLine.close();
    }

    @Override
    public boolean isOpen() {
        return targetLine.isOpen();
    }

    @Override
    public Control[] getControls() {
        return new Control[0];
    }

    @Override
    public boolean isControlSupported(Control.Type control) {
        return false;
    }

    @Override
    public Control getControl(Control.Type control) {
        throw new IllegalArgumentException("Unsupported control: " + control);
    }

    @Override
    public void addLineListener(LineListener listener) {
        targetLine.addLineListener(listener);
    }

    @Override
    public void removeLineListener(LineListener listener) {
        targetLine.removeLineListener(listener);
    }

    @Override
    public Line.Info getLineInfo() {
        return new Line.Info(Mixer.class) {};
    }

    @Override
    public boolean isSynchronizationSupported(Line[] lines, boolean maintainSync) {
        return false;
    }

    @Override
    public void synchronize(Line[] lines, boolean maintainSync) {
    }

    @Override
    public void unsynchronize(Line[] lines) {
    }
}
