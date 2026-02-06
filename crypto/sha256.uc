/*
 * https://github.com/geraintluff/sha256
 */

const sha256h = [ 6074000999, 7439101573, 9603838834, 11363415354, 14244795007, 15485724812, 17708603819, 18721328409, 20597939549, 23129106730, 23913365850, 26125266136, 27501209191, 28163984007, 29444812301, 31267833885, 32990269782, 33544766931, 35155822461, 36190037706, 36696216663, 38174504342, 39129014274, 40518640433, 42300522161, 43163887121, 43589157362, 44427487166, 44840775015, 45656128617, 48401823285, 49158147581, 50271303326, 50636917621, 52426757166, 52777441725, 53815785970, 54834471676, 55503209459, 56491474797, 57462746098, 57782875294, 59357628979, 59667592596, 60282738678, 60587969685, 62388003650, 64137539151, 64710207113, 64994648955, 65559830454, 66398583069, 66675822617, 68045078899, 68853563647, 69652664639, 70442701224, 70704085058, 71482502113, 71996771349, 72252533331, 73517997888, 75253906414, 75742573278 ];
const sha256k = [ 5411319704, 6194414737, 7344290767, 8215976869, 9551921755, 10098905585, 11043570340, 11460697813, 12214315672, 13195500289, 13492127166, 14311783875, 14809980276, 15046980094, 15499789991, 16133124468, 16720292289, 16907126662, 17444216262, 17784676812, 17950125167, 18429019306, 18734950876, 19175934170, 19734090066, 20001703533, 20132865992, 20390182855, 20516441075, 20764397895, 21588763473, 21813078375, 22141143685, 22248366392, 22769593852, 22871018771, 23170020180, 23461497531, 23651862830, 23931792517, 24205322401, 24295138891, 24734567280, 24820601251, 24990902297, 25075189284, 25569408389, 26045227120, 26200031510, 26276752392, 26428864332, 26653801653, 26727943347, 27092625994, 27306805839, 27517677555, 27725365998, 27793908591, 27997534228, 28131656200, 28198240250, 28526537963, 28973835255, 29099129074 ];

function rightRotate(value, amount)
{
	return (((value >> 1) & 0x7fffffff) >> (amount - 1)) | (value << (32 - amount));
};

function rightShift(value, amount)
{
	return (((value >> 1) & 0x7fffffff) >> (amount - 1));
}

export function hash(data)
{
	const maxWord = 0x100000000;
	const words = [];
	const dataBitLength = length(data) * 8;

	// Initial hash value: first 32 bits of the fractional parts of the square roots of the first 8 primes
	let hash = sha256h;
	// Round constants: first 32 bits of the fractional parts of the cube roots of the first 64 primes
	const k = sha256k;

	data += chr(128); // Append '1' bit (plus zero padding)
	while (length(data) % 64 - 56) {
		data += chr(0); // More zero padding
	}
	for (let i = 0; i < length(data); i++) {
		const j = ord(data, i);
		words[i >> 2] |= j << ((3 - i) & 3) * 8;
	}
	words[length(words)] = ((dataBitLength / maxWord) | 0);
	words[length(words)] = (dataBitLength);

	// process each chunk
	for (let j = 0; j < length(words);) {
		const w = slice(words, j, j += 16); // The message is expanded into 64 words as part of the iteration
		const oldHash = hash;
		// This is now the "working hash", often labelled as variables a...g
		// (we have to truncate as well, otherwise extra entries at the end accumulate
		hash = slice(hash, 0, 8);

		for (let i = 0; i < 64; i++) {
			// Expand the message into 64 words
			// Used below if 
			const w15 = w[i - 15], w2 = w[i - 2];

			// Iterate
			const a = hash[0], e = hash[4];
			const temp1 = hash[7]
				+ (rightRotate(e, 6) ^ rightRotate(e, 11) ^ rightRotate(e, 25)) // S1
				+ ((e & hash[5]) ^ ((~e) & hash[6])) // ch
				+ k[i]
				// Expand the message schedule if needed
				+ (w[i] = (i < 16) ? w[i] : (
					w[i - 16]
					+ (rightRotate(w15, 7) ^ rightRotate(w15, 18) ^ rightShift(w15, 3)) // s0
					+ w[i - 7]
					+ (rightRotate(w2, 17) ^ rightRotate(w2, 19) ^ rightShift(w2, 10)) // s1
				) | 0
				);
			// This is only used once, so *could* be moved below, but it only saves 4 bytes and makes things unreadble
			const temp2 = (rightRotate(a, 2) ^ rightRotate(a, 13) ^ rightRotate(a, 22)) // S0
				+ ((a & hash[1]) ^ (a & hash[2]) ^ (hash[1] & hash[2])); // maj

			hash = [0xffffffff & (temp1 + temp2) | 0, ...hash];
			hash[4] = (hash[4] + temp1) | 0;
		}

		for (let i = 0; i < 8; i++) {
			hash[i] = (hash[i] + oldHash[i]) | 0;
		}
	}

	return [
		(hash[0] >> 24) & 255, (hash[0] >> 16) & 255, (hash[0] >> 8) & 255, hash[0] & 255,
		(hash[1] >> 24) & 255, (hash[1] >> 16) & 255, (hash[1] >> 8) & 255, hash[1] & 255,
		(hash[2] >> 24) & 255, (hash[2] >> 16) & 255, (hash[2] >> 8) & 255, hash[2] & 255,
		(hash[3] >> 24) & 255, (hash[3] >> 16) & 255, (hash[3] >> 8) & 255, hash[3] & 255,
		(hash[4] >> 24) & 255, (hash[4] >> 16) & 255, (hash[4] >> 8) & 255, hash[4] & 255,
		(hash[5] >> 24) & 255, (hash[5] >> 16) & 255, (hash[5] >> 8) & 255, hash[5] & 255,
		(hash[6] >> 24) & 255, (hash[6] >> 16) & 255, (hash[6] >> 8) & 255, hash[6] & 255,
		(hash[7] >> 24) & 255, (hash[7] >> 16) & 255, (hash[7] >> 8) & 255, hash[7] & 255
	];
};
