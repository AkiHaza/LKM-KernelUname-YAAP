#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/stop_machine.h>
#include <linux/string.h>
#include <linux/utsname.h>

#define KM_FIELD_LEN (__NEW_UTS_LEN + 1)

static bool enabled;
module_param(enabled, bool, 0444);
MODULE_PARM_DESC(enabled, "Apply the configured UTS values at module load");

static char spoof_sysname[KM_FIELD_LEN];
module_param_string(sysname, spoof_sysname, sizeof(spoof_sysname), 0444);
MODULE_PARM_DESC(sysname, "Replacement uname sysname; empty preserves the value");

static char spoof_nodename[KM_FIELD_LEN];
module_param_string(nodename, spoof_nodename, sizeof(spoof_nodename), 0444);
MODULE_PARM_DESC(nodename, "Replacement uname nodename; empty preserves the value");

static char spoof_release[KM_FIELD_LEN];
module_param_string(release, spoof_release, sizeof(spoof_release), 0444);
MODULE_PARM_DESC(release, "Replacement kernel release; empty preserves the value");

static char spoof_version[KM_FIELD_LEN];
module_param_string(version, spoof_version, sizeof(spoof_version), 0444);
MODULE_PARM_DESC(version,
	"Replacement kernel version/build string; empty preserves the value");

static char spoof_machine[KM_FIELD_LEN];
module_param_string(machine, spoof_machine, sizeof(spoof_machine), 0444);
MODULE_PARM_DESC(machine, "Replacement uname machine; empty preserves the value");

static char spoof_domainname[KM_FIELD_LEN];
module_param_string(domainname, spoof_domainname, sizeof(spoof_domainname), 0444);
MODULE_PARM_DESC(domainname,
	"Replacement uname domainname; empty preserves the value");

static bool applied;
module_param_named(applied, applied, bool, 0444);
MODULE_PARM_DESC(applied, "Whether KernelMask changed the namespace");

static struct uts_namespace *target_namespace;
static struct new_utsname original_name;
static unsigned int changed_fields;

static bool kernelmask_valid_field(const char *value)
{
	const unsigned char *cursor = (const unsigned char *)value;

	while (*cursor) {
		if (*cursor < 0x20 || *cursor > 0x7e || *cursor == '"' ||
		    *cursor == '\'' || *cursor == '\\')
			return false;
		cursor++;
	}

	return true;
}

enum kernelmask_field {
	KM_SYSNAME = BIT(0),
	KM_NODENAME = BIT(1),
	KM_RELEASE = BIT(2),
	KM_VERSION = BIT(3),
	KM_MACHINE = BIT(4),
	KM_DOMAINNAME = BIT(5),
};

static void kernelmask_apply_field(char *destination, const char *replacement,
				   unsigned int field)
{
	if (!replacement[0])
		return;

	strscpy_pad(destination, replacement, KM_FIELD_LEN);
	changed_fields |= field;
}

static void kernelmask_restore_field(char *destination, const char *original,
				     const char *replacement, unsigned int field)
{
	if (!(changed_fields & field))
		return;

	if (strncmp(destination, replacement, KM_FIELD_LEN) == 0)
		strscpy_pad(destination, original, KM_FIELD_LEN);
}

static int kernelmask_apply_stop(void *unused)
{
	original_name = target_namespace->name;
	changed_fields = 0;
	kernelmask_apply_field(target_namespace->name.sysname, spoof_sysname,
				      KM_SYSNAME);
	kernelmask_apply_field(target_namespace->name.nodename, spoof_nodename,
				      KM_NODENAME);
	kernelmask_apply_field(target_namespace->name.release, spoof_release,
				      KM_RELEASE);
	kernelmask_apply_field(target_namespace->name.version, spoof_version,
				      KM_VERSION);
	kernelmask_apply_field(target_namespace->name.machine, spoof_machine,
				      KM_MACHINE);
	kernelmask_apply_field(target_namespace->name.domainname,
				      spoof_domainname, KM_DOMAINNAME);
	applied = changed_fields != 0;
	return 0;
}

static int kernelmask_restore_stop(void *unused)
{
	kernelmask_restore_field(target_namespace->name.sysname,
					original_name.sysname, spoof_sysname, KM_SYSNAME);
	kernelmask_restore_field(target_namespace->name.nodename,
					original_name.nodename, spoof_nodename, KM_NODENAME);
	kernelmask_restore_field(target_namespace->name.release,
					original_name.release, spoof_release, KM_RELEASE);
	kernelmask_restore_field(target_namespace->name.version,
					original_name.version, spoof_version, KM_VERSION);
	kernelmask_restore_field(target_namespace->name.machine,
					original_name.machine, spoof_machine, KM_MACHINE);
	kernelmask_restore_field(target_namespace->name.domainname,
					original_name.domainname, spoof_domainname,
					KM_DOMAINNAME);
	applied = false;
	return 0;
}

static int __init kernelmask_init(void)
{
	const char *fields[] = {
		spoof_sysname, spoof_nodename, spoof_release, spoof_version,
		spoof_machine, spoof_domainname,
	};
	size_t index;
	int ret;

	if (!enabled) {
		pr_info("disabled; no UTS values changed\n");
		return 0;
	}
	for (index = 0; index < ARRAY_SIZE(fields); index++) {
		if (!kernelmask_valid_field(fields[index])) {
			pr_err("field %zu contains an unsupported character\n", index);
			return -EINVAL;
		}
	}

	target_namespace = &init_uts_ns;
	ret = stop_machine(kernelmask_apply_stop, NULL, NULL);
	if (ret) {
		pr_err("stop_machine apply failed: %d\n", ret);
		return ret;
	}

	pr_info("loaded: namespace=%p changed_fields=0x%x\n", target_namespace,
		changed_fields);
	return 0;
}

static void __exit kernelmask_exit(void)
{
	int ret;

	if (!target_namespace || !applied)
		return;

	ret = stop_machine(kernelmask_restore_stop, NULL, NULL);
	if (ret) {
		pr_err("stop_machine restore failed: %d\n", ret);
		return;
	}

	pr_info("unloaded: UTS values restored where unchanged\n");
}

module_init(kernelmask_init);
module_exit(kernelmask_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("YAAP KernelMask contributors");
MODULE_DESCRIPTION("Scoped UTS metadata override for YAAP LKM compatibility testing");
