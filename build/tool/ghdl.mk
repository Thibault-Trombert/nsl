GHDL=ghdl
target ?= $(top-entity)

simulate: $(target).ghw

.PRECIOUS: $(target).ghw

.PHONY: FORCE

_GHDL_STD_93=93c
_GHDL_STD_08=08
_GHDL_CF_SUFFIX_93=93
_GHDL_CF_SUFFIX_08=08
workdir = $(if $(filter $(top-lib),$1),,ghdl-build/$1/)
lib_cf = $(call workdir,$1)$1-obj$(_GHDL_CF_SUFFIX_$($1-vhdl-version)).cf

define ghdl-source-run
$(GHDL) $1 \
		--workdir=$(call workdir,$($2-library)) \
		$(foreach l,$($($2-library)-libdeps-unsorted),-Pghdl-build/$l) \
		--std=$(_GHDL_STD_$($($2-library)-vhdl-version)) \
		-v \
		--work=$($2-library) \
		$2
	$(SILENT)
endef

define vhdl-source-do
$(call ghdl-source-run,-a,$1)
	$(SILENT)$(call ghdl-source-run,-i,$1)
	$(SILENT)
endef

define ghdl-library-rules

$(call lib_cf,$1): $(foreach l,$($1-libdeps-unsorted),$(call lib_cf,$($l-library))) $($1-sources) $(MAKEFILE_LIST)
	$(SILENT)echo Updating $1
	$(SILENT)echo   packages: $($1-packages)
	$(SILENT)echo   lib deps: $($1-libdeps-unsorted)
	$(SILENT)mkdir -p $$(dir $$@)
	$(SILENT)$(foreach s,$($1-sources),$(call $($s-language)-source-do,$s))

clean-dirs += $(if $(filter $1,$(top-lib)),,$(call lib_cf,$1))

$(target): $(call lib_cf,$1)

endef

clean-dirs += ghdl-build

$(eval $(foreach l,$(libraries),$(call ghdl-library-rules,$l)))

$(target): FORCE
	$(SILENT)$(GHDL) -e -v \
		$(GHDL_OPTS) \
		$(sort $(foreach l,$(filter %.cf,$^),-P$(dir $l))) \
		$(top-entity)

$(target).ghw: $(target)
	$(SILENT)$(GHDL) -r -v \
		$(GHDL_OPTS) \
		$(sort $(foreach l,$(filter %.cf,$^),-P$(dir $l))) \
		$(top-entity) --wave=$@

clean-files += *.o $(top) $(top).ghw $(top).vcd *.cf *.lst $(target)
