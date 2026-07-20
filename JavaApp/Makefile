# Prerequisite variables
SOURCEDIR := src
OUTPUTDIR := build

SOURCES := $(shell find $(SOURCEDIR) -type f -name '*.java')
CLASSES := $(SOURCES:$(SOURCEDIR)/%.java=$(OUTPUTDIR)/%.class)

TARGETS := $(shell find $(SOURCEDIR) -mindepth 1 -maxdepth 1 -type d)
TARGETS := $(TARGETS:$(SOURCEDIR)/%=$(OUTPUTDIR)/%.jar)

# Add all jars to classpath and allow compiling with private API
JCFLAGS := -cp "$(subst $() $(),:,$(wildcard $(SOURCEDIR)/*/):$(wildcard libs/*/*.jar))" -XDignore.symbol.file

all: $(TARGETS)
	
# Sometimes the CI produces empty class file resulting in broken jar, so we check and abort here
check_empty_classes:
	@set -e
	@echo "Checking for empty class files"
	$(eval EMPTY_CLASSES := $(shell find $(OUTPUTDIR) -name '*.class' -size 0))
	@if [ -n "$(EMPTY_CLASSES)" ]; then \
		echo "Error: found empty class files in $@: $(EMPTY_CLASSES)"; \
		exit 1; \
	fi

# Rules for building java class
$(CLASSES): $(OUTPUTDIR)/%.class: $(SOURCEDIR)/%.java
	@set -e
	$(eval TARGET=$(word 2, $(subst /, ,$@)))
	@mkdir -p $(OUTPUTDIR)/classes
	@mkdir -p $(dir $@)
	@echo "Compiling $<"
	@$(BOOTJDK)/javac $(JCFLAGS) -d $(OUTPUTDIR)/classes $<
	@cp $(@:$(OUTPUTDIR)/$(TARGET)/%.class=$(OUTPUTDIR)/classes/%*.class) $(dir $@)/

$(OUTPUTDIR)/launcher.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@cp -r $(SOURCEDIR)/launcher/META-INF $(basename $@)/ 2>/dev/null || true
	@$(BOOTJDK)/jar -cf $@ -C $(basename $@) .

$(OUTPUTDIR)/lwjgl.jar: $(CLASSES) check_empty_classes
	@set -e
	@echo "Creating $@"
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib
	@cd $(OUTPUTDIR)/lwjgl_lib && find ../../libs/lwjgl -name 'lwjgl*.jar' -exec $(BOOTJDK)/jar -xf {} \; && rm -rf META-INF
	@cd $(OUTPUTDIR)/lwjgl_lib && $(BOOTJDK)/jar -xf "../../../lwjgl.jar" && rm -rf META-INF
	@cp -R $(OUTPUTDIR)/lwjgl/* $(OUTPUTDIR)/lwjgl_lib/
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib/com/apple/ios/audio
	@cp -R $(OUTPUTDIR)/launcher/com/apple/ios/audio/*.class $(OUTPUTDIR)/lwjgl_lib/com/apple/ios/audio/
	@mkdir -p $(OUTPUTDIR)/lwjgl_lib/META-INF/services
	@cp $(SOURCEDIR)/launcher/META-INF/services/javax.sound.sampled.spi.MixerProvider $(OUTPUTDIR)/lwjgl_lib/META-INF/services/
	@$(BOOTJDK)/jar -cf $@ -C $(OUTPUTDIR)/lwjgl_lib .

$(OUTPUTDIR)/patchjna_agent.jar: $(CLASSES)
	@set -e
	@mv $(basename $@)/com/sun/jna/Platform.class $(basename $@)/com/sun/jna/Platform.class.patch
	@echo "Creating $@"
	@$(BOOTJDK)/jar -cfm $@ $(SOURCEDIR)/patchjna_agent.txt -C $(basename $@) .

clean:
	rm -rf $(OUTPUTDIR)

.SUFFIXES: .java
.PHONY: all clean
