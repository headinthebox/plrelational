import Foundation

func show(name: String, _ relation: Relation) {
    print("\(name) is:")
    print("---")
    print(relation)
    print("---")
    print("")
}

do {
    let r = MakeRelation(["A",  "B",  "C"],
                         ["A1", "B1", "C1"],
                         ["A1", "B2", "C1"],
                         ["A2", "B1", "C2"]
    )
    let s = MakeRelation(["A",  "B",  "C"],
                         ["A1", "B2", "C1"],
                         ["A2", "B2", "C1"],
                         ["A2", "B2", "C2"]
    )
    
    show("r", r)
    show("s", s)
    
    show("r.union(s)", r.union(s))
    show("r.intersection(s)", r.intersection(s))
    show("r.difference(s)", r.difference(s))
}

do {
    let a = MakeRelation(
        ["A", "B"],
        ["X", "1"],
        ["Y", "2"]
    )
    let b = MakeRelation(
        ["B", "C"],
        ["1", "T"],
        ["3", "V"]
    )
    
    show("a.join(b)", a.join(b))
}

do {
    let a = MakeRelation(
        ["A", "B"],
        ["X", "1"],
        ["Y", "1"]
    )
    
    show("a.project(B)", a.project(["B"]))
}

do {
    var FLIGHTS = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
    )
    
    show("FLIGHTS", FLIGHTS)
    
    FLIGHTS.add(["NUMBER": "117", "FROM": "Atlanta", "TO": "Boston", "DEPARTS": "10:05p", "ARRIVES": "12:43a"])
    show("FLIGHTS.add", FLIGHTS)
    
    FLIGHTS.delete(["NUMBER": "83"])
    show("FLIGHTS.delete", FLIGHTS)
    
    show("FLIGHTS.select", FLIGHTS.select(["FROM": "Boston"]))
    
    FLIGHTS.change(["NUMBER": "109"], to: ["DEPARTS": "9:40p", "ARRIVES": "2:42a"])
    show("FLIGHTS.change", FLIGHTS)
}

do {
    var FLIGHTS = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "11:30a",  "1:43p"],
        ["84",     "O'Hare", "JFK",         "3:00p",   "5:55p"],
        ["109",    "JFK",    "Los Angeles", "9:50p",   "2:52a"],
        ["213",    "JFK",    "Boston",      "11:43a",  "12:45p"],
        ["214",    "Boston", "O'Hare",      "2:20p",   "3:12p"]
    )
    
    show("FLIGHTS", FLIGHTS.project(["DEPARTS", "ARRIVES"]))
    
    show("FLIGHTS", FLIGHTS.project(["DEPARTS"]))
    show("FLIGHTS", FLIGHTS.project(["FROM"]))
}

do {
    let usable = MakeRelation(
        ["FLIGHT", "EQUIPMENT"],
        ["83", "727"],
        ["83", "747"],
        ["84", "727"],
        ["84", "747"],
        ["109", "707"]
    )
    show("usable", usable)
    
    show("usable.select", usable.select(["FLIGHT": "84", "EQUIPMENT": "727"]))
    
    let certified = MakeRelation(
        ["PILOT", "EQUIPMENT"],
        ["Simmons", "707"],
        ["Simmons", "727"],
        ["Barth", "747"],
        ["Hill", "727"],
        ["Hill", "747"]
    )
    show("certified", certified)
    
    let options = usable.join(certified)
    show("options", options)
    
    options.project(["FLIGHT", "PILOT"])
    show("options", options)
    
    let r = MakeRelation(
        ["A", "B"],
        ["A1", "B1"],
        ["A2", "B1"]
    )
    show("r", r)
    
    let s = MakeRelation(
        ["C", "D"],
        ["C1", "D1"],
        ["C2", "D1"],
        ["C2", "D2"]
    )
    show("s", s)
    
    show("r.join(s)", r.join(s))
    
    show("options.select", options.select(["FLIGHT": "84"]))
    
    let flight84 = MakeRelation(["FLIGHT"], ["84"])
    show("options.join(flight84)", options.join(flight84))
}

do {
    
    let q = MakeRelation(
        ["EQUIPMENT"],
        ["707"],
        ["727"],
        ["747"]
    )
    
    let s = MakeRelation(
        ["EQUIPMENT"],
        ["707"]
    )
    
    let certified = MakeRelation(
        ["PILOT", "EQUIPMENT"],
        ["Desmond", "707"],
        ["Desmond", "727"],
        ["Desmond", "747"],
        ["Doyle", "707"],
        ["Doyle", "727"],
        ["Davis", "707"],
        ["Davis", "727"],
        ["Davis", "747"],
        ["Davis", "1011"],
        ["Dow", "727"]
        ).setDefaultSort("PILOT")
    
    show("certified.divide(q)", certified.divide(q))
    show("certified.divide(s)", certified.divide(s))
}

do {
    let pilots = (["PILOT": "Desmond"] as ConcreteRelation).join(["EQUIPMENT": "707"] as ConcreteRelation).union((["PILOT": "Davis"] as ConcreteRelation).join(["EQUIPMENT": "707"] as ConcreteRelation))
    show("pilots", pilots)
}

do {
    
    let usedfor = MakeRelation(
        ["FLIGHT", "DATE",  "PLANENUM"],
        ["12",     "6 Jan", "707-82"],
        ["12",     "7 Jan", "707-82"],
        ["13",     "6 Jan", "707-82"],
        ["26",     "6 Jan", "747-16"],
        ["26",     "7 Jan", "747-18"],
        ["27",     "6 Jan", "747-16"],
        ["27",     "7 Jan", "747-2"],
        ["60",     "6 Jan", "707-82"],
        ["60",     "7 Jan", "727-6"]
    )
    show("usedfor", usedfor)
    
    var usedforRenamed = usedfor.renameAttributes(["FLIGHT": "FLIGHT2"])
    show("usedforRenamed", usedforRenamed)
    
    show("usedfor.join(usedforRenamed)", usedfor.join(usedforRenamed).project(["FLIGHT", "FLIGHT2"]))
    
    show("usedforRenamed renamed more", usedforRenamed.renameAttributes(["DATE": "PLANENUM", "PLANENUM": "DATE"]))
}

do {
    var routes = MakeRelation(
        ["NUMBER", "FROM",    "TO"],
        ["84",     "O'Hare",  "JFK"],
        ["109",    "JFK",     "Los Angeles"],
        ["117",    "Atlanta", "Boston"],
        ["213",    "JFK",     "Boston"],
        ["214",    "Boston",  "JFK"]
    )
    show("routes", routes)
    
    var based = MakeRelation(
        ["PILOT", "AIRPORT"],
        ["Terhune", "JFK"],
        ["Temple", "Atlanta"],
        ["Taylor", "Atlanta"],
        ["Tarbell", "Boston"],
        ["Todd", "Los Angeles"],
        ["Truman", "O'Hare"]
    )
    show("based", based)
    
    show("routes.equijoin(based)", routes.equijoin(based, matching: ["FROM": "AIRPORT"]))
}

do {
    var FLIGHTS = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
        ["84",     "O'Hare", "JFK",         "1500",    "1755"],
        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
        ["213",    "JFK",    "Boston",      "1143",    "1245"],
        ["214",    "Boston", "O'Hare",      "1420",    "1512"]
    )
    
    let times = FLIGHTS.project(["NUMBER", "DEPARTS", "ARRIVES"])
    
    show("times", times)
    
    show("arrives before 1300", times.select([ComparisonTerm(Attribute("ARRIVES"), LTComparator(), "1300")]))
    
    let twoHoursLT = AnyComparator({ (lhs, rhs) in
        let lhsN = Int(lhs) ?? -1
        let rhsN = Int(rhs) ?? -1
        return ((rhsN + 2400) - lhsN) % 2400 >= 200
    })
    
    show("longer than two hours", times.select([ComparisonTerm(Attribute("DEPARTS"), twoHoursLT, Attribute("ARRIVES"))]))
}

do {
    let timesab = MakeRelation(
        ["NUMBER", "DEPARTS", "ARRIVES"],
        ["60",  "0940", "1145"],
        ["91",  "1250", "1447"],
        ["112", "1605", "1815"],
        ["306", "2030", "2225"],
        ["40",  "2115", "2311"]
    )
    let timesbc = MakeRelation(
        ["NUMBER", "DEPARTS", "ARRIVES"],
        ["11",  "0830", "0952"],
        ["60",  "1225", "1343"],
        ["156", "1620", "1740"],
        ["158", "1910", "2035"]
    )
    
    let connectac = timesab.thetajoin(timesbc.renamePrime(), terms: [ComparisonTerm(Attribute("ARRIVES"), LTComparator(), Attribute("DEPARTS'"))])
    show("connectac", connectac)
}

do {
    var FLIGHTS = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
        ["84",     "O'Hare", "JFK",         "1500",    "1755"],
        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
        ["213",    "JFK",    "Boston",      "1143",    "1245"],
        ["214",    "Boston", "O'Hare",      "1420",    "1512"]
    )
    
    let split = FLIGHTS.split([ComparisonTerm(Attribute("FROM"), EqualityComparator(), "JFK")])
    show("FROM JFK", split.0)
    show("Other", split.1)
}

do {
//    var FLIGHTS = MakeRelation(
//        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
//        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
//        ["84",     "O'Hare", "JFK",         "1500",    "1755"],
//        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
//        ["213",    "JFK",    "Boston",      "1143",    "1245"],
//        ["215",    "JFK",    "Boston",      "1144",    "1246"],
//        ["216",    "JFK",    "Boston",      "1145",    "1247"],
//        ["214",    "Boston", "O'Hare",      "1420",    "1512"]
//    )
//    
//    let factored = FLIGHTS.factor(["FROM", "TO"], link: "LINK")
//    show("factored 1", factored.0)
//    show("factored 2", factored.1)
}

do {
    var FLIGHTS = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
        ["84",     "O'Hare", "JFK",         "1130",    "1755"],
        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
        ["213",    "JFK",    "Boston",      "1143",    "1245"],
        ["215",    "JFK",    "Boston",      "1144",    "1246"],
        ["216",    "JFK",    "Boston",      "1145",    "1247"],
        ["214",    "Boston", "O'Hare",      "1420",    "1512"]
    )
    
    show("FLIGHTS", FLIGHTS)
    print("FROM and TO determine NUMBER: \(FLIGHTS.satisfies(FunctionalDependency(["FROM", "TO"], determines: ["NUMBER"])))")
    print("FROM and DEPARTS determine NUMBER: \(FLIGHTS.satisfies(FunctionalDependency(["FROM", "DEPARTS"], determines: ["NUMBER"])))")
    print("---")
    print()
    print("FLIGHTS satisfies:")
    for fd in FLIGHTS.allSatisfiedFunctionalDependencies() {
        print("\t\(fd)")
    }
    print("NUMBER/FROM satisfies: \(FLIGHTS.project(["NUMBER", "FROM"]).allSatisfiedFunctionalDependencies())")
    print("---")
    print()
}

do {
    let db = SimpleDatabase()
    
    db["FLIGHTS"] = MakeRelation(
        ["NUMBER", "FROM",   "TO",          "DEPARTS", "ARRIVES"],
        ["83",     "JFK",    "O'Hare",      "1130",    "1343"],
        ["84",     "O'Hare", "JFK",         "1130",    "1755"],
        ["109",    "JFK",    "Los Angeles", "2150",    "0252"],
        ["213",    "JFK",    "Boston",      "1143",    "1245"],
        ["215",    "JFK",    "Boston",      "1144",    "1246"],
        ["216",    "JFK",    "Boston",      "1145",    "1247"],
        ["214",    "Boston", "O'Hare",      "1420",    "1512"]
    )
    
    db["USABLE"] = MakeRelation(
        ["NUMBER", "EQUIPMENT"],
        ["83", "727"],
        ["83", "747"],
        ["84", "727"],
        ["84", "747"],
        ["109", "707"]
    )
    
    print(db)
    
    show("joined", db["FLIGHTS"].join(db["USABLE"]))
    
    let plist = db.toPlist()
    print(plist)
    let db2 = SimpleDatabase.fromPlist(plist)
    print(db2)
}

do {
    let flight = FLIGHT(number: 123, departs: "Here", arrives: "There")
    print(flight)
    print(flight.toRow())
    print(FLIGHT.fromRow(flight.toRow()))
}

do {
    let flights = [
        FLIGHT(number: 42, departs: "Earth", arrives: "Space"),
        FLIGHT(number: 99, departs: "JFK", arrives: "JFK"),
        FLIGHT(number: 123, departs: "Airport", arrives: "Another Airport"),
        FLIGHT(number: 124, departs: "Q", arrives: "R"),
    ]
    
    var relation = MakeRelation(["number", "departs", "arrives"])
    flights.map({ $0.toRow() }).forEach({ relation.add($0) })
    
    show("flights", relation)
    
    let flights2 = relation.rows().map(FLIGHT.fromRow)
    print(flights2)
}

do {
    let dbpath = "/tmp/whatever.sqlite3"
    _ = try? NSFileManager.defaultManager().removeItemAtPath(dbpath)
    
    let db = try! SQLiteDatabase(dbpath)
    try! db.createRelation("FLIGHTS", scheme: ["NUMBER", "FROM", "TO"])
    
    let FLIGHTS = db["FLIGHTS"]
    try! FLIGHTS.add(["NUMBER": "123", "FROM": "JFK", "TO": "Unknown"])
    try! FLIGHTS.add(["NUMBER": "888", "FROM": "Here", "TO": "There"])
    try! FLIGHTS.add(["NUMBER": "3", "FROM": "Atlanta", "TO": "Atlanta"])
    
    for r in FLIGHTS.rows() {
        print(r)
    }
    
    print(FLIGHTS)
}
