/* The check for enumerator-name (mgf-enumerator-name.c): a Windows program, run under a
 * NotProton runner.
 *
 * It takes the first device SetupAPI lists and asks its enumerator name the way EA SPORTS
 * FC 27 does, CM_Get_DevNode_Registry_PropertyA with CM_DRP_ENUMERATOR_NAME, and the wide way:
 * with the fix both answer the first component of the device's instance id, and a buffer too
 * small gets CR_BUFFER_SMALL with the length needed; without it, on Wine 11.21, the question
 * fails with a length of 0.
 *
 * Prints one line per check and exits 0 when the name was answered right, 2 when it was not
 * answered, 1 on anything wrong.
 *
 * Part of MacGameFix -- https://github.com/MathiasKowoll/MacGameFix
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    HDEVINFO set = SetupDiGetClassDevsW(NULL, NULL, NULL, DIGCF_ALLCLASSES);
    SP_DEVINFO_DATA device = {sizeof(device)};
    char id[MAX_DEVICE_ID_LEN + 1], name[64], *slash;
    WCHAR nameW[64];
    ULONG len, type = 0;
    CONFIGRET r;
    unsigned i;

    if (set == INVALID_HANDLE_VALUE || !SetupDiEnumDeviceInfo(set, 0, &device)) { printf("FAIL: no device to ask\n"); return 1; }
    if (CM_Get_Device_IDA(device.DevInst, id, sizeof(id), 0) != CR_SUCCESS) { printf("FAIL: no id for the device\n"); return 1; }
    if (!(slash = strchr(id, '\\'))) { printf("FAIL: the id %s has no enumerator\n", id); return 1; }
    printf("ok: the device is %s\n", id);
    *slash = 0;

    len = sizeof(name);
    r = CM_Get_DevNode_Registry_PropertyA(device.DevInst, CM_DRP_ENUMERATOR_NAME, &type, name, &len, 0);
    if (r != CR_SUCCESS) { printf("not answered: CM_DRP_ENUMERATOR_NAME gives %lu, length %lu\n", r, len); return 2; }
    if (type != REG_SZ || len != strlen(id) + 1 || strcmp(name, id))
    { printf("FAIL: the enumerator is \"%s\", length %lu, type %lu, not \"%s\"\n", name, len, type, id); return 1; }
    printf("ok: CM_Get_DevNode_Registry_PropertyA answers \"%s\", length %lu\n", name, len);

    len = sizeof(nameW);
    r = CM_Get_DevNode_Registry_PropertyW(device.DevInst, CM_DRP_ENUMERATOR_NAME, &type, nameW, &len, 0);
    if (r != CR_SUCCESS || len != (strlen(id) + 1) * sizeof(WCHAR)) { printf("FAIL: the wide question gives %lu, length %lu\n", r, len); return 1; }
    for (i = 0; id[i]; i++) if (nameW[i] != (WCHAR)id[i]) { printf("FAIL: the wide name differs at %u\n", i); return 1; }
    printf("ok: CM_Get_DevNode_Registry_PropertyW answers the same\n");

    len = 1;
    r = CM_Get_DevNode_Registry_PropertyA(device.DevInst, CM_DRP_ENUMERATOR_NAME, NULL, name, &len, 0);
    if (r != CR_BUFFER_SMALL || len != strlen(id) + 1) { printf("FAIL: a buffer of 1 gives %lu, length %lu\n", r, len); return 1; }
    printf("ok: a buffer too small gets CR_BUFFER_SMALL and the length needed\n");
    return 0;
}
