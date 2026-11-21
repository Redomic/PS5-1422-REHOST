/*
 * PS5 Sony southbridge HPET model for QEMU (hardware-supply track, L-345..L-355).
 *
 * The genuine 14.22 kernel's hpet_pci driver requires the HPET to be FUNCTION 5 of
 * a Sony SoC root device 0x104d:0x90eb (Titania F0): pci_attach (FUN_80518d70) scans
 * the bus and, on finding 0x104d:0x90eb, runs its ARI function-enumeration fn_loop
 * (FUN_805101d0), which writes each function's devinfo+0x168 = function index (so the
 * HPET at function 5 gets +0x168=5, the value hpet_pci's Aeolia branch demands) AND
 * creates the functions early enough for the probe pass. fn_loop needs funchigh==0xff
 * (full ARI) or it panics. So both the root and the HPET are modeled as PCIe + ARI,
 * placed behind a pcie-root-port (see session121.sh), with:
 *   - titania-f0 (function 0): 0x104d:0x90eb root, the gate pci_attach keys on;
 *   - aeolia-hpet (function 5): subsystem 104d:90a1 + the HPET aperture aliased onto
 *     QEMU's real HPET at BAR+0x109000.
 */
#include "qemu/osdep.h"
#include "qemu/module.h"
#include "hw/pci/pci.h"
#include "hw/pci/pci_device.h"
#include "hw/pci/pcie.h"
#include "exec/address-spaces.h"
#include "qom/object.h"

/* ---- aeolia-hpet: HPET at function 5 (subsystem 104d:90a1) ---- */
#define TYPE_AEOLIA_HPET "aeolia-hpet"
OBJECT_DECLARE_SIMPLE_TYPE(AeoliaHpetState, AEOLIA_HPET)

struct AeoliaHpetState {
    PCIDevice parent_obj;
    MemoryRegion bar;
    MemoryRegion hpet_alias;
};

#define AEOLIA_BAR_SIZE   0x200000
#define HPET_APERTURE_OFF 0x109000
#define QEMU_HPET_BASE    0xfed00000
#define QEMU_HPET_SIZE    0x400

static void aeolia_hpet_realize(PCIDevice *pci_dev, Error **errp)
{
    AeoliaHpetState *s = AEOLIA_HPET(pci_dev);

    memory_region_init(&s->bar, OBJECT(s), "aeolia-hpet-bar", AEOLIA_BAR_SIZE);
    memory_region_init_alias(&s->hpet_alias, OBJECT(s), "aeolia-hpet-hpet",
                             get_system_memory(), QEMU_HPET_BASE, QEMU_HPET_SIZE);
    memory_region_add_subregion(&s->bar, HPET_APERTURE_OFF, &s->hpet_alias);
    pci_register_bar(pci_dev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->bar);
}

static void aeolia_hpet_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->realize   = aeolia_hpet_realize;
    k->vendor_id = 0x104d;
    k->device_id = 0x90a1;                 /* Aeolia (the HPET function identity) */
    k->revision  = 0x05;
    k->class_id  = PCI_CLASS_SYSTEM_OTHER;
    k->subsystem_vendor_id = 0x104d;
    k->subsystem_id        = 0x90a1;
    dc->desc = "PS5 HPET function (Aeolia 104d:90a1; QEMU HPET aliased at +0x109000)";
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo aeolia_hpet_info = {
    .name          = TYPE_AEOLIA_HPET,
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(AeoliaHpetState),
    .class_init    = aeolia_hpet_class_init,
    .interfaces    = (InterfaceInfo[]) {
        { INTERFACE_CONVENTIONAL_PCI_DEVICE },
        { },
    },
};

/* ---- titania-f0: the 0x104d:0x90eb root pci_attach keys on (function 0) ---- */
#define TYPE_TITANIA_F0 "titania-f0"
OBJECT_DECLARE_SIMPLE_TYPE(TitaniaF0State, TITANIA_F0)

struct TitaniaF0State {
    PCIDevice parent_obj;
    MemoryRegion bar;
};

static void titania_f0_realize(PCIDevice *pci_dev, Error **errp)
{
    TitaniaF0State *s = TITANIA_F0(pci_dev);

    memory_region_init(&s->bar, OBJECT(s), "titania-f0-bar", 0x1000);
    pci_register_bar(pci_dev, 0, PCI_BASE_ADDRESS_SPACE_MEMORY, &s->bar);

    pcie_endpoint_cap_init(pci_dev, 0xa0);
    pcie_ari_init(pci_dev, 0x100);
}

static void titania_f0_class_init(ObjectClass *klass, void *data)
{
    DeviceClass *dc = DEVICE_CLASS(klass);
    PCIDeviceClass *k = PCI_DEVICE_CLASS(klass);

    k->realize   = titania_f0_realize;
    k->vendor_id = 0x104d;
    k->device_id = 0x90eb;                 /* Titania F0 root -- the pci_attach gate */
    k->revision  = 0x01;
    k->class_id  = PCI_CLASS_SYSTEM_OTHER;
    k->subsystem_vendor_id = 0x104d;
    k->subsystem_id        = 0x90eb;
    dc->desc = "PS5 Titania F0 root (104d:90eb) -- triggers the Sony ARI fn enumeration";
    set_bit(DEVICE_CATEGORY_MISC, dc->categories);
}

static const TypeInfo titania_f0_info = {
    .name          = TYPE_TITANIA_F0,
    .parent        = TYPE_PCI_DEVICE,
    .instance_size = sizeof(TitaniaF0State),
    .class_init    = titania_f0_class_init,
    .interfaces    = (InterfaceInfo[]) {
        { INTERFACE_PCIE_DEVICE },
        { },
    },
};

static void sony_hpet_register_types(void)
{
    type_register_static(&aeolia_hpet_info);
    type_register_static(&titania_f0_info);
}
type_init(sony_hpet_register_types)
