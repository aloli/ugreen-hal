/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026 Philippe Nénert (ALOLI sas)
 *
 * ugreen-led-ctl — pilotage des LED de façade et de baies des NAS UGREEN
 * NASync sous FreeBSD, via la pile smbus(4).
 *
 * STATUT : jamais exécuté sur matériel réel. Le protocole est rétro-
 * documenté à partir de l'implémentation Linux de référence
 * (miskcoo/ugreen_leds_controller) — voir docs/protocol-i2c-leds.adoc.
 * Ce fichier est le livrable de l'étape 3.2 du plan ; l'étape 3.3 consiste
 * à l'exécuter sur le DXP2800 et à retranscrire ce qui se passe.
 *
 * INCERTITUDE PRINCIPALE, à trancher au premier essai
 * ---------------------------------------------------
 * Le code Linux de référence utilise I2C_SMBUS_I2C_BLOCK_DATA, une
 * transaction I2C brute qui n'émet PAS d'octet de longueur. SMB_BWRITE de
 * FreeBSD implémente le « Block Write » du standard SMBus, lequel insère
 * un octet de comptage entre la commande et les données :
 *
 *   Linux  (I2C block) : [adresse][commande][d0][d1]...[dn]
 *   FreeBSD (SMBus blk): [adresse][commande][n][d0][d1]...[dn]
 *
 * Si le microcontrôleur UGREEN attend la première forme, cet octet
 * supplémentaire décalera toute la trame et la commande sera rejetée —
 * silencieusement, le plus probablement. Dans ce cas, le repli est de
 * passer par iic(4) et I2CRDWR, qui permet d'émettre la trame exacte.
 * Ne pas conclure trop vite à une erreur d'adresse ou de somme de contrôle
 * avant d'avoir écarté cette piste.
 */

#include <sys/types.h>
#include <sys/ioctl.h>

#include <dev/smbus/smb.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

/*
 * Adresse du contrôleur, en convention FreeBSD (8 bits).
 *
 * La console Linux d'UGOS rapporte 0x3a, mais Linux exprime les adresses
 * I2C sur 7 bits : il faut décaler d'un bit. 0x3a << 1 == 0x74. Utiliser
 * 0x3a tel quel sous FreeBSD ne désigne aucun périphérique.
 */
#define UGREEN_LED_SLAVE	0x74

#define UGREEN_LED_COUNT	4

/* Registres : lecture en 0x81 + identifiant, écriture en 0x00 + identifiant. */
#define UGREEN_REG_READ_BASE	0x81
#define UGREEN_REG_WRITE_BASE	0x00
#define UGREEN_REG_LAST_STATUS	0x80

#define UGREEN_READ_LEN		11
#define UGREEN_WRITE_LEN	12

/* Sous-commandes, octet 0x05 du bloc d'écriture. */
#define UGREEN_OP_BRIGHTNESS	0x01
#define UGREEN_OP_COLOR		0x02
#define UGREEN_OP_ONOFF		0x03
#define UGREEN_OP_BLINK		0x04
#define UGREEN_OP_BREATH	0x05

/* États rapportés par l'octet 0x00 du bloc de lecture. */
static const char *const led_states[] = {
	"éteinte", "allumée", "clignotante", "respiration"
};

static const char *const led_names[UGREEN_LED_COUNT] = {
	"power", "netdev", "disk1", "disk2"
};

static const char *device_path = "/dev/smb0";

static void
usage(void)
{
	fprintf(stderr,
	    "usage: ugreen-led-ctl [-d device] status <led>\n"
	    "       ugreen-led-ctl [-d device] on|off <led>\n"
	    "       ugreen-led-ctl [-d device] brightness <led> <0-255>\n"
	    "       ugreen-led-ctl [-d device] color <led> <r> <g> <b>\n"
	    "\n"
	    "led : power | netdev | disk1 | disk2 | <numéro>\n"
	    "device par défaut : /dev/smb0\n");
	exit(EX_USAGE);
}

/*
 * Somme de contrôle : addition simple des octets, sur 16 bits, transmise
 * en gros-boutiste. Aucune retenue ni complément — vérifié sur le code de
 * référence.
 */
static uint16_t
checksum(const uint8_t *data, size_t len)
{
	uint32_t sum = 0;
	size_t i;

	for (i = 0; i < len; i++)
		sum += data[i];

	return ((uint16_t)(sum & 0xffff));
}

static int
led_by_name(const char *name)
{
	int i;
	char *end;
	long value;

	for (i = 0; i < UGREEN_LED_COUNT; i++) {
		if (strcmp(name, led_names[i]) == 0)
			return (i);
	}

	value = strtol(name, &end, 0);
	if (*name != '\0' && *end == '\0' && value >= 0 && value < 256)
		return ((int)value);

	return (-1);
}

/*
 * Envoie un bloc de 12 octets. `led` sert à la fois d'octet de commande
 * (0x00 + identifiant) et de premier octet des données : ce n'est pas une
 * redondance accidentelle, le protocole de référence procède ainsi.
 */
static int
ugreen_write(int fd, uint8_t led, uint8_t op, const uint8_t *params,
    size_t nparams)
{
	struct smbcmd cmd;
	uint8_t block[UGREEN_WRITE_LEN];
	uint16_t sum;

	if (nparams > 4) {
		warnx("trop de paramètres pour la sous-commande 0x%02x", op);
		return (-1);
	}

	memset(block, 0, sizeof(block));
	block[0] = led;
	block[1] = 0xa0;
	block[2] = 0x01;
	block[3] = 0x00;
	block[4] = 0x00;
	block[5] = op;
	if (nparams > 0)
		memcpy(&block[6], params, nparams);

	/* La somme couvre les octets 0x01 à 0x09, pas l'identifiant. */
	sum = checksum(&block[1], 9);
	block[10] = (uint8_t)(sum >> 8);
	block[11] = (uint8_t)(sum & 0xff);

	memset(&cmd, 0, sizeof(cmd));
	cmd.slave = UGREEN_LED_SLAVE;
	cmd.cmd = (u_char)(UGREEN_REG_WRITE_BASE + led);
	cmd.wbuf = (char *)block;
	cmd.wcount = (int)sizeof(block);

	if (ioctl(fd, SMB_BWRITE, &cmd) < 0) {
		warn("SMB_BWRITE (led %u, sous-commande 0x%02x)", led, op);
		return (-1);
	}

	return (0);
}

static int
ugreen_read(int fd, uint8_t led, uint8_t *out)
{
	struct smbcmd cmd;

	memset(&cmd, 0, sizeof(cmd));
	cmd.slave = UGREEN_LED_SLAVE;
	cmd.cmd = (u_char)(UGREEN_REG_READ_BASE + led);
	cmd.rbuf = (char *)out;
	cmd.rcount = UGREEN_READ_LEN;

	if (ioctl(fd, SMB_BREAD, &cmd) < 0) {
		warn("SMB_BREAD (led %u)", led);
		return (-1);
	}

	return (0);
}

static int
cmd_status(int fd, uint8_t led)
{
	uint8_t block[UGREEN_READ_LEN];
	uint16_t expected, got;

	if (ugreen_read(fd, led, block) < 0)
		return (1);

	expected = checksum(block, 9);
	got = (uint16_t)((block[9] << 8) | block[10]);

	printf("led         : %u\n", led);
	printf("état        : %s (%u)\n",
	    block[0] < 4 ? led_states[block[0]] : "inconnu", block[0]);
	printf("luminosité  : %u\n", block[1]);
	printf("couleur RVB : %u %u %u\n", block[2], block[3], block[4]);
	printf("cycle       : %u ms\n", (block[5] << 8) | block[6]);
	printf("allumé      : %u ms\n", (block[7] << 8) | block[8]);

	if (expected != got) {
		warnx("somme de contrôle incohérente : lue 0x%04x, "
		    "calculée 0x%04x", got, expected);
		return (1);
	}

	return (0);
}

int
main(int argc, char *argv[])
{
	int ch, fd, led, rc;
	const char *action;
	uint8_t params[4];

	while ((ch = getopt(argc, argv, "d:")) != -1) {
		switch (ch) {
		case 'd':
			device_path = optarg;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;

	if (argc < 2)
		usage();

	action = argv[0];
	led = led_by_name(argv[1]);
	if (led < 0)
		errx(EX_USAGE, "identifiant de LED inconnu : %s", argv[1]);

	fd = open(device_path, O_RDWR);
	if (fd < 0) {
		warn("ouverture de %s", device_path);
		/*
		 * Piège vérifié le 21/07/2026 sur le banc QEMU : charger
		 * ichsmb(4) ne suffit pas. Trois modules distincts
		 * interviennent, et seul le dernier crée un device node :
		 *
		 *   ichsmb(4) attache le contrôleur SMBus du PCH ;
		 *   smbus(4)  fournit le bus lui-même ;
		 *   smb(4)    expose /dev/smbN à l'espace utilisateur.
		 *
		 * `kldload smb` tire les deux autres par dépendance ; charger
		 * ichsmb seul donne un bus fonctionnel mais invisible depuis
		 * l'espace utilisateur, et donc exactement cette erreur.
		 */
		fprintf(stderr,
		    "\nPistes, dans l'ordre :\n"
		    "  kldload smb          charge smb(4), qui crée /dev/smbN\n"
		    "                       (tire ichsmb et smbus par dépendance)\n"
		    "  ls -l /dev/smb*      vérifier que le device node existe\n"
		    "  dmesg | grep -i smb  vérifier que le contrôleur est attaché\n"
		    "\nSur une plateforme non Intel, le pilote de contrôleur peut\n"
		    "être intpm(4) plutôt que ichsmb(4).\n");
		exit(EX_OSFILE);
	}

	rc = 0;
	if (strcmp(action, "status") == 0) {
		rc = cmd_status(fd, (uint8_t)led);
	} else if (strcmp(action, "on") == 0 || strcmp(action, "off") == 0) {
		params[0] = (strcmp(action, "on") == 0) ? 1 : 0;
		rc = ugreen_write(fd, (uint8_t)led, UGREEN_OP_ONOFF,
		    params, 1) < 0;
	} else if (strcmp(action, "brightness") == 0) {
		if (argc < 3)
			usage();
		params[0] = (uint8_t)strtol(argv[2], NULL, 0);
		rc = ugreen_write(fd, (uint8_t)led, UGREEN_OP_BRIGHTNESS,
		    params, 1) < 0;
	} else if (strcmp(action, "color") == 0) {
		if (argc < 5)
			usage();
		params[0] = (uint8_t)strtol(argv[2], NULL, 0);
		params[1] = (uint8_t)strtol(argv[3], NULL, 0);
		params[2] = (uint8_t)strtol(argv[4], NULL, 0);
		rc = ugreen_write(fd, (uint8_t)led, UGREEN_OP_COLOR,
		    params, 3) < 0;
	} else {
		close(fd);
		usage();
	}

	close(fd);
	return (rc);
}
