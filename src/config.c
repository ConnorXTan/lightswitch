#include "config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <errno.h>

void ls_config_defaults(ls_config *c)
{
    memset(c, 0, sizeof(*c));
    ls_detector_config_defaults(&c->detector);
    ls_action_none(&c->on_tap);
    ls_action_none(&c->on_double_tap);
    ls_action_none(&c->on_hold);
    ls_action_none(&c->on_cover);
    ls_action_none(&c->on_uncover);
    c->poll_ms = 100.0;
}

static int parse_double(const char *value, double *out, char *err, size_t errlen,
                        const char *key)
{
    char  *end = NULL;
    double v   = strtod(value, &end);
    if (end == value || *end != '\0') {
        snprintf(err, errlen, "%s: \"%s\" is not a number", key, value);
        return -1;
    }
    *out = v;
    return 0;
}

static int parse_int(const char *value, int *out, char *err, size_t errlen,
                     const char *key)
{
    char *end = NULL;
    long  v   = strtol(value, &end, 10);
    if (end == value || *end != '\0') {
        snprintf(err, errlen, "%s: \"%s\" is not an integer", key, value);
        return -1;
    }
    *out = (int)v;
    return 0;
}

int ls_config_set(ls_config *c, const char *key, const char *value,
                  char *err, size_t errlen)
{
    if (!strcasecmp(key, "on_tap"))
        return ls_action_parse(value, &c->on_tap, err, errlen);
    if (!strcasecmp(key, "on_double_tap"))
        return ls_action_parse(value, &c->on_double_tap, err, errlen);
    if (!strcasecmp(key, "on_hold"))
        return ls_action_parse(value, &c->on_hold, err, errlen);
    if (!strcasecmp(key, "on_cover"))
        return ls_action_parse(value, &c->on_cover, err, errlen);
    if (!strcasecmp(key, "on_uncover"))
        return ls_action_parse(value, &c->on_uncover, err, errlen);

    if (!strcasecmp(key, "poll_ms"))
        return parse_double(value, &c->poll_ms, err, errlen, key);
    if (!strcasecmp(key, "calibration_ms"))
        return parse_double(value, &c->detector.calibration_ms, err, errlen, key);
    if (!strcasecmp(key, "min_baseline_lux"))
        return parse_double(value, &c->detector.min_baseline_lux, err, errlen, key);
    if (!strcasecmp(key, "cover_ratio"))
        return parse_double(value, &c->detector.cover_ratio, err, errlen, key);
    if (!strcasecmp(key, "uncover_ratio"))
        return parse_double(value, &c->detector.uncover_ratio, err, errlen, key);
    if (!strcasecmp(key, "hold_ms"))
        return parse_double(value, &c->detector.hold_ms, err, errlen, key);
    if (!strcasecmp(key, "double_gap_ms"))
        return parse_double(value, &c->detector.double_gap_ms, err, errlen, key);
    if (!strcasecmp(key, "refractory_ms"))
        return parse_double(value, &c->detector.refractory_ms, err, errlen, key);
    if (!strcasecmp(key, "baseline_alpha"))
        return parse_double(value, &c->detector.baseline_alpha, err, errlen, key);
    if (!strcasecmp(key, "debounce_samples"))
        return parse_int(value, &c->detector.debounce_samples, err, errlen, key);
    if (!strcasecmp(key, "switch_mode"))
        return parse_int(value, &c->detector.switch_mode, err, errlen, key);

    snprintf(err, errlen, "unknown setting \"%s\"", key);
    return -1;
}

int ls_config_set_assignment(ls_config *c, const char *assignment,
                             char *err, size_t errlen)
{
    const char *eq = strchr(assignment, '=');
    if (!eq) {
        snprintf(err, errlen, "expected key=value, got \"%s\"", assignment);
        return -1;
    }

    char key[64];
    size_t klen = (size_t)(eq - assignment);
    if (klen == 0 || klen >= sizeof(key)) {
        snprintf(err, errlen, "bad setting name in \"%s\"", assignment);
        return -1;
    }
    memcpy(key, assignment, klen);
    key[klen] = '\0';
    while (klen > 0 && isspace((unsigned char)key[klen - 1]))
        key[--klen] = '\0';

    const char *value = eq + 1;
    while (*value && isspace((unsigned char)*value))
        value++;

    return ls_config_set(c, key, value, err, errlen);
}

int ls_config_load_file(ls_config *c, const char *path, char *err, size_t errlen)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        if (errno == ENOENT)
            return 0;
        snprintf(err, errlen, "cannot read %s: %s", path, strerror(errno));
        return -1;
    }

    char line[LS_ACTION_CMD_MAX + 128];
    long lineno = 0;
    while (fgets(line, sizeof(line), fp)) {
        lineno++;

        char *p = line;
        while (*p && isspace((unsigned char)*p))
            p++;
        if (*p == '\0' || *p == '#')
            continue;

        char *nl = p + strlen(p);
        while (nl > p && (nl[-1] == '\n' || nl[-1] == '\r'))
            *--nl = '\0';
        while (nl > p && isspace((unsigned char)nl[-1]))
            *--nl = '\0';
        if (*p == '\0')
            continue;

        char reason[192];
        if (ls_config_set_assignment(c, p, reason, sizeof(reason)) != 0) {
            snprintf(err, errlen, "%s:%ld: %s", path, lineno, reason);
            fclose(fp);
            return -1;
        }
    }
    fclose(fp);
    return 1;
}

int ls_config_default_path(char *buf, size_t buflen)
{
    const char *xdg = getenv("XDG_CONFIG_HOME");
    if (xdg && *xdg) {
        snprintf(buf, buflen, "%s/lightswitch/config", xdg);
        return 0;
    }
    const char *home = getenv("HOME");
    if (!home || !*home)
        return -1;
    snprintf(buf, buflen, "%s/.config/lightswitch/config", home);
    return 0;
}

int ls_config_has_bindings(const ls_config *c)
{
    return c->on_tap.kind        != LS_ACTION_NONE ||
           c->on_double_tap.kind != LS_ACTION_NONE ||
           c->on_hold.kind       != LS_ACTION_NONE ||
           c->on_cover.kind      != LS_ACTION_NONE ||
           c->on_uncover.kind    != LS_ACTION_NONE;
}
