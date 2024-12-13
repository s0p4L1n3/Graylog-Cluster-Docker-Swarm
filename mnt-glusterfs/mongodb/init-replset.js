// Script d'initialisation du replicaset

var rsConfig = {
  _id: "rs0",
  members: [
    { _id: 0, host: "mongodb01:27017" },
    { _id: 1, host: "mongodb02:27017" },
    { _id: 2, host: "mongodb03:27017" }
  ]
};

// Verify if replicaset is already initialized
try {
  var status = rs.status();
  print("Replicaset déjà initialisé.");
} catch (e) {
  print("Initialisation du replicaset...");
  var result = rs.initiate(rsConfig);

  if (result.ok === 1) {
    print("Replicaset initialisé avec succès.");
  } else {
    print("Échec de l'initialisation : " + tojson(result));
  }
}
