use("mongodbVSCodePlaygroundDB");

db.users.drop();
db.customers.drop();
db.employees.drop();
db.sellers.drop();
db.products.drop();
db.orders.drop();
db.payments.drop();
db.shippings.drop();
db.warehouses.drop();
db.sequences.drop();
db.product_categories.drop();

db.sequences.insertOne({ _id: "order_seq", sequence_value: 0 });

function getNextSequenceValue(sequenceName) {
  const sequenceDoc = db.sequences.findOneAndUpdate(
    { _id: sequenceName },
    { $inc: { sequence_value: 1 } },
    { returnDocument: "after" }
  );
  return sequenceDoc.sequence_value;
}

// Collection Creation
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["userid", "name", "email", "contact", "address", "role"],
      properties: {
        userid: { bsonType: "string" },
        name: { bsonType: "string" },
        email: {
          bsonType: "string",
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+.[a-zA-Z]{2,}$",
        },
        contact: { bsonType: "string" },
        address: {
          bsonType: "object",
          required: ["street", "city", "district"],
          properties: {
            street: { bsonType: "string" },
            city: { bsonType: "string" },
            district: { bsonType: "string" },
          },
        },
        role: { enum: ["customer", "seller", "employee"] },
      },
    },
  },
});

db.createCollection("customers", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["customerid", "userid"],
      properties: {
        customerid: { bsonType: "string" },
        userid: { bsonType: "string" },
      },
    },
  },
});

db.createCollection("sellers", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["sellerid", "userid"],
      properties: {
        sellerid: { bsonType: "string" },
        userid: { bsonType: "string" },
      },
    },
  },
});

db.createCollection("employees", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["employeeid", "userid"],
      properties: {
        employeeid: { bsonType: "string" },
        userid: { bsonType: "string" },
      },
    },
  },
});

db.createCollection("product_categories", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["categoryid", "categoryname", "description"],
      properties: {
        categoryid: { bsonType: "string" },
        categoryname: { bsonType: "string" },
        description: { bsonType: "string" },
      },
    },
  },
});

db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "productid",
        "productname",
        "price",
        "category",
        "stockquantity",
        "status",
        "sellerid",
      ],
      properties: {
        productid: { bsonType: "string" },
        productname: { bsonType: "string" },
        price: { bsonType: "double" },
        category: {
          bsonType: "object",
          required: ["categoryid", "categoryname", "description"],
          properties: {
            categoryid: { bsonType: "string" },
            categoryname: { bsonType: "string" },
            description: { bsonType: "string" },
          },
        },
        stockquantity: { bsonType: "int" },
        status: { enum: ["available", "out of stock"] },
        sellerid: { bsonType: "string" },
      },
    },
  },
});

db.createCollection("payments", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["paymentid", "amount", "transactionstatus"],
      properties: {
        paymentid: { bsonType: "string" },
        amount: { bsonType: "double", minimum: 0 },
        transactionstatus: { enum: ["pending", "completed", "failed"] },
      },
    },
  },
});

db.createCollection("shippings", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["shippingid", "trackingno", "deliverystatus", "address"],
      properties: {
        shippingid: { bsonType: "string" },
        trackingno: { bsonType: "string" },
        deliverystatus: {
          enum: ["pending", "shipped", "delivered", "returned"],
        },
        address: {
          bsonType: "object",
          required: ["street", "city", "district"],
          properties: {
            street: { bsonType: "string" },
            city: { bsonType: "string" },
            district: { bsonType: "string" },
          },
        },
      },
    },
  },
});

db.createCollection("orders", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "orderid",
        "orderdate",
        "status",
        "customerid",
        "payment",
        "shippingid",
        "productid",
        "quantity",
      ],
      properties: {
        orderid: { bsonType: "string" },
        orderdate: { bsonType: "date" },
        status: { enum: ["pending", "processing", "shipped", "delivered"] },
        customerid: { bsonType: "string" },
        payment: {
          bsonType: "object",
          required: ["paymentid", "amount", "transactionstatus"],
          properties: {
            paymentid: { bsonType: "string" },
            amount: { bsonType: "double" },
            transactionstatus: { enum: ["pending", "completed", "failed"] },
          },
        },
        shippingid: { bsonType: "string" },
        productid: { bsonType: "array", items: { bsonType: "string" } },
        quantity: { bsonType: "array", items: { bsonType: "int" } },
      },
    },
  },
});

db.createCollection("warehouses", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["warehouseid", "location", "capacity", "employeeid"],
      properties: {
        warehouseid: { bsonType: "string" },
        location: { bsonType: "string" },
        capacity: { bsonType: "int" },
        employeeid: { bsonType: "objectId" },
      },
    },
  },
});

// Triggers
function watchProductStatus() {
  const changeStream = db.products.watch([
    { $match: { operationType: { $in: ["insert", "update"] } } },
  ]);
  changeStream.on("change", (change) => {
    const status =
      change.fullDocument?.status ||
      change.updateDescription?.updatedFields?.status;
    if (status && !["available", "out of stock"].includes(status)) {
      throw new Error('Status must be "available" or "out of stock"');
    }
  });
}

function watchOrderDeletion() {
  const changeStream = db
    .collection("orders")
    .watch([{ $match: { operationType: "delete" } }]);
  changeStream.on("change", () => {
    throw new Error(
      "Deletion of orders is not allowed to maintain transaction history."
    );
  });
}

function watchOrderInsert() {
  const changeStream = db.orders.watch([
    { $match: { operationType: "insert" } },
  ]);
  changeStream.on("change", (change) => {
    const order = change.fullDocument;
    const product = db.products.findOne({ productid: order.productid });
    if (!product) {
      throw new Error("Product not found for order.");
    }
    const expectedAmount = product.price * order.quantity;
    if (Math.abs(order.payment.amount - expectedAmount) > 0.01) {
      throw new Error("Payment amount does not match order cost.");
    }
  });
}

// Functions imitating stored procedures
function placeOrder(customerid, productids, payment, shipping, quantities) {
  const session = db.getMongo().startSession();
  session.startTransaction();
  try {
    const orderid = `ORD-${new Date()
      .toISOString()
      .slice(0, 10)
      .replace(/-/g, "")}-${String(getNextSequenceValue("order_seq")).padStart(
      6,
      "0"
    )}`;
    const customer = db.customers.findOne({ customerid });
    if (!customer) throw new Error("Customer not found");

    const existingShipping = db.shippings.findOne({
      shippingid: shipping.shippingid,
    });
    if (existingShipping) {
      throw new Error(`Shipping ID ${shipping.shippingid} already exists.`);
    }

    print(`Inserting shipping: ${shipping.shippingid}`);
    const shippingInsert = db.shippings.insertOne(shipping);
    const shippingRef = shipping.shippingid;

    print(`Inserting payment: ${payment.paymentid}`);
    const paymentInsert = db.payments.insertOne(payment);

    for (let i = 0; i < productids.length; i++) {
      const product = db.products.findOne({ productid: productids[i] });
      if (!product) throw new Error(`Product ${productids[i]} not found`);
      if (product.stockquantity < quantities[i])
        throw new Error(`Insufficient stock for product ${productids[i]}`);
      db.products.updateOne(
        { productid: productids[i] },
        { $inc: { stockquantity: -quantities[i] } }
      );
    }

    db.orders.insertOne({
      orderid,
      orderdate: new Date(),
      status: "pending",
      customerid: customerid,
      payment,
      shippingid: shippingRef,
      productid: productids,
      quantity: quantities,
    });

    session.commitTransaction();
  } catch (error) {
    session.abortTransaction();
    throw error;
  } finally {
    session.endSession();
  }
}

// add_customer
function addCustomer(userid, customerid) {
  const user = db.users.findOne({ userid });
  if (!user) throw new Error("User not found");
  db.customers.insertOne({
    customerid,
    userid,
  });
}

// add_seller
function addSeller(userid, sellerid) {
  const user = db.users.findOne({ userid });
  if (!user) throw new Error("User not found");
  db.sellers.insertOne({
    sellerid,
    userid,
  });
}

// add_employee
function addEmployee(userid, employeeid) {
  const user = db.users.findOne({ userid });
  if (!user) throw new Error("User not found");
  db.employees.insertOne({
    employeeid,
    userid,
  });
}

// add_product_category
function addProductCategory(categoryid, categoryname, description) {
  db.product_categories.insertOne({
    categoryid,
    categoryname,
    description,
  });
}

// add_product
function addProduct(
  productid,
  productname,
  price,
  categoryid,
  stockquantity,
  status,
  sellerid
) {
  const category = db.product_categories.findOne({ categoryid });
  if (!category) throw new Error("Category not found");
  db.products.insertOne({
    productid,
    productname,
    price,
    category,
    stockquantity,
    status,
    sellerid,
  });
}

// add_warehouse
function addWarehouse(warehouseid, location, capacity, employeeid) {
  const employee = db.employees.findOne({ employeeid });
  if (!employee) throw new Error("Employee not found");
  db.warehouses.insertOne({
    warehouseid,
    location,
    capacity,
    employeeid: employeeid,
  });
}

//Function mimicking the SQL function `generate_invoice`
function generateInvoice(orderid) {
  try {
    // Fetch orders matching the orderid prefix
    const orders = db.orders
      .find({ orderid: new RegExp(`^${orderid}`) })
      .toArray();
    if (orders.length === 0) {
      return `Error: No order found for ID ${orderid}`;
    }

    // Get shared details from the first order
    const firstOrder = orders[0];
    const customer = db.customers.findOne({
      customerid: firstOrder.customerid,
    });
    if (!customer) {
      return `Error: Customer ${firstOrder.customerid} not found`;
    }
    const user = db.users.findOne({ userid: customer.userid });
    if (!user) {
      return `Error: User ${customer.userid} not found`;
    }
    const shipping = db.shippings.findOne({
      shippingid: firstOrder.shippingid,
    });
    if (!shipping) {
      return `Error: Shipping ${firstOrder.shippingid} not found`;
    }

    // Build invoice header
    let invoice =
      `INVOICE\n-------\n` +
      `Order ID: ${orderid}\n` +
      `Order Date: ${firstOrder.orderdate.toLocaleDateString("en-GB", {
        day: "2-digit",
        month: "short",
        year: "numeric",
      })}\n` +
      `Customer: ${user.name} (${user.email})\n` +
      `Billing Address: ${user.address.street}, ${user.address.city}, ${user.address.district}\n` +
      `Shipping Address: ${shipping.address.street}, ${shipping.address.city}, ${shipping.address.district}\n` +
      `Shipping Status: ${shipping.deliverystatus}\n` +
      `Payment Status: ${firstOrder.payment.transactionstatus}\n\n` +
      `Items:\n---------------------------------------------\n` +
      `${"Product".padEnd(20)}${"Quantity".padEnd(10)}${"Price".padEnd(
        10
      )}Subtotal\n` +
      `---------------------------------------------\n`;

    // Process line items
    let total = 0;
    let lineItems = "";
    orders.forEach((order) => {
      const product = db.products.findOne({ productid: order.productid });
      if (!product) {
        return `Error: Product ${order.productid} not found`;
      }
      const subtotal = product.price * order.quantity;
      total += subtotal;
      lineItems += `${product.productname.padEnd(20)}${order.quantity
        .toString()
        .padEnd(10)}${product.price.toFixed(2).padEnd(10)}${subtotal.toFixed(
        2
      )}\n`;
    });

    invoice += lineItems;
    invoice += `---------------------------------------------\n`;
    invoice += `Total: ${total.toFixed(2)}\n`;

    // Validate payment amount
    if (Math.abs(total - firstOrder.payment.amount) > 0.01) {
      invoice += `\nWarning: Payment amount (${firstOrder.payment.amount.toFixed(
        2
      )}) does not match total (${total.toFixed(2)})`;
    }

    return invoice;
  } catch (error) {
    return `Error generating invoice: ${error.message}`;
  }
}

// Insertion statements
function insertUsers(data) {
  data.forEach((user) => db.users.insertOne(user));
}

function insertCustomers(data) {
  data.forEach((customer) => addCustomer(customer.userid, customer.customerid));
}

function insertSellers(data) {
  data.forEach((seller) => addSeller(seller.userid, seller.sellerid));
}

function insertEmployees(data) {
  data.forEach((employee) => addEmployee(employee.userid, employee.employeeid));
}

function insertProductCategories(data) {
  data.forEach((category) =>
    addProductCategory(
      category.categoryid,
      category.categoryname,
      category.description
    )
  );
}

function insertProducts(data) {
  data.forEach((product) => {
    const seller = db.sellers.findOne({ sellerid: product.sellerid });
    if (!seller) throw new Error(`seller ${product.sellerid} not found`);
    addProduct(
      product.productid,
      product.productname,
      product.price,
      product.categoryid,
      product.stockquantity,
      product.status,
      product.sellerid
    );
  });
}

function insertWarehouses(data) {
  data.forEach((warehouse) =>
    addWarehouse(
      warehouse.warehouseid,
      warehouse.location,
      warehouse.capacity,
      warehouse.employeeid
    )
  );
}

function insertOrders(data) {
  data.forEach((order, index) => {
    print(order);
    try {
      print(`Placing order ${index + 1} for customer ${order.customerid}...`);
      placeOrder(
        order.customerid,
        order.productids,
        order.payment,
        order.shipping,
        order.quantities
      );
      print(`Order ${index + 1} placed successfully.`);
    } catch (error) {
      print(`Error placing order ${index + 1}: ${error.message}`);
    }
  });
}

// Arrays with sample data
const users = [
  {
    _id: 1234,
    userid: "U001",
    name: "Pako Mampane",
    email: "pako@gmail.com",
    contact: "71234567",
    address: { street: "123 Mogoma St", city: "Gaborone", district: "SE" },
    role: "customer",
  },
  {
    userid: "U002",
    name: "Carol Maundo",
    email: "carol@gmail.com",
    contact: "72345678",
    address: { street: "456 Thito St", city: "Gaborone", district: "SE" },
    role: "customer",
  },
  {
    userid: "U003",
    name: "Thabiso Podi",
    email: "thabiso@gmail.com",
    contact: "73456789",
    address: { street: "789 Bojanala St", city: "Gaborone", district: "SE" },
    role: "customer",
  },
  {
    userid: "U004",
    name: "Lefika Paulson",
    email: "lefika@gmail.com",
    contact: "74567890",
    address: { street: "321 Khama St", city: "Gaborone", district: "SE" },
    role: "employee",
  },
  {
    userid: "U005",
    name: "Boris Mathata",
    email: "boris@gmail.com",
    contact: "74567890",
    address: { street: "654 Lerole St", city: "Gaborone", district: "SE" },
    role: "customer",
  },
  {
    userid: "U006",
    name: "Tom Harris",
    email: "tom@gmail.com",
    contact: "74567890",
    address: { street: "987 Mathata St", city: "Francistown", district: "NE" },
    role: "seller",
  },
  {
    userid: "U007",
    name: "Tkay Nyams",
    email: "tkay@gmail.com",
    contact: "74567890",
    address: { street: "147 Sekgoma St", city: "Francistown", district: "NE" },
    role: "customer",
  },
  {
    userid: "U008",
    name: "David Bolele",
    email: "david@gmail.com",
    contact: "78901234",
    address: { street: "258 Bakgatla St", city: "Francistown", district: "NE" },
    role: "employee",
  },
  {
    userid: "U009",
    name: "Bonya Maraks",
    email: "bonya@gmail.com",
    contact: "79012345",
    address: { street: "369 Lesedi St", city: "Francistown", district: "NE" },
    role: "customer",
  },
  {
    userid: "U010",
    name: "Thuto Lesedi",
    email: "thuto@gmail.com",
    contact: "72123456",
    address: { street: "741 Koma St", city: "Francistown", district: "NE" },
    role: "seller",
  },
];
const customers = [
  { customerid: "C001", userid: "U001" },
  { customerid: "C002", userid: "U002" },
  { customerid: "C003", userid: "U003" },
  { customerid: "C004", userid: "U007" },
];
const sellers = [
  { sellerid: "S001", userid: "U006" },
  { sellerid: "S002", userid: "U010" },
];
const employees = [
  { employeeid: "E001", userid: "U008" },
  { employeeid: "E002", userid: "U009" },
];
const categories = [
  {
    categoryid: "CAT001",
    categoryname: "Electronics",
    description: "Electronic devices",
  },
  {
    categoryid: "CAT002",
    categoryname: "Clothing",
    description: "Fashion items",
  },
  {
    categoryid: "CAT003",
    categoryname: "Books",
    description: "Literature and textbooks",
  },
  { categoryid: "CAT004", categoryname: "Toys", description: "Children toys" },
  {
    categoryid: "CAT005",
    categoryname: "Furniture",
    description: "Home furniture",
  },
  {
    categoryid: "CAT006",
    categoryname: "Appliances",
    description: "Kitchen appliances",
  },
  {
    categoryid: "CAT007",
    categoryname: "Sports",
    description: "Sporting goods",
  },
  {
    categoryid: "CAT008",
    categoryname: "Jewelry",
    description: "Fashion jewelry",
  },
  {
    categoryid: "CAT009",
    categoryname: "Beauty",
    description: "Beauty products",
  },
  {
    categoryid: "CAT010",
    categoryname: "Automotive",
    description: "Car accessories",
  },
];
const products = [
  {
    productid: "P001",
    productname: "Laptop",
    price: 999.99,
    categoryid: "CAT001",
    stockquantity: 50,
    status: "available",
    sellerid: "S001",
  },
  {
    productid: "P002",
    productname: "T-Shirt",
    price: 19.99,
    categoryid: "CAT002",
    stockquantity: 100,
    status: "available",
    sellerid: "S001",
  },
  {
    productid: "P003",
    productname: "Book",
    price: 29.99,
    categoryid: "CAT003",
    stockquantity: 30,
    status: "available",
    sellerid: "S002",
  },
  {
    productid: "P004",
    productname: "Toy Car",
    price: 15.99,
    categoryid: "CAT004",
    stockquantity: 80,
    status: "available",
    sellerid: "S001",
  },
  {
    productid: "P005",
    productname: "Chair",
    price: 89.99,
    categoryid: "CAT005",
    stockquantity: 20,
    status: "available",
    sellerid: "S002",
  },
  {
    productid: "P006",
    productname: "Blender",
    price: 49.99,
    categoryid: "CAT006",
    stockquantity: 40,
    status: "available",
    sellerid: "S002",
  },
  {
    productid: "P007",
    productname: "Tennis Racket",
    price: 39.99,
    categoryid: "CAT007",
    stockquantity: 60,
    status: "available",
    sellerid: "S002",
  },
  {
    productid: "P008",
    productname: "Necklace",
    price: 199.99,
    categoryid: "CAT008",
    stockquantity: 10,
    status: "available",
    sellerid: "S001",
  },
  {
    productid: "P009",
    productname: "Lipstick",
    price: 9.99,
    categoryid: "CAT009",
    stockquantity: 200,
    status: "available",
    sellerid: "S002",
  },
  {
    productid: "P010",
    productname: "Car Mat",
    price: 24.99,
    categoryid: "CAT010",
    stockquantity: 70,
    status: "available",
    sellerid: "S001",
  },
];
const orders = [
  {
    customerid: "C001",
    productids: ["P001", "P002"],
    payment: {
      paymentid: "PAY014",
      amount: 2019.97,
      transactionstatus: "pending",
    },
    shipping: {
      shippingid: "SHIP010",
      trackingno: "TRACK010",
      deliverystatus: "pending",
      address: { street: "789 Bojanala St", city: "Gaborone", district: "SE" },
    },
    quantities: [2, 1],
  },
  {
    customerid: "C002",
    productids: ["P003"],
    payment: {
      paymentid: "PAY015",
      amount: 89.97,
      transactionstatus: "completed",
    },
    shipping: {
      shippingid: "SHIP011",
      trackingno: "TRACK011",
      deliverystatus: "pending",
      address: { street: "456 Thito St", city: "Gaborone", district: "SE" },
    },
    quantities: [3],
  },
  {
    customerid: "C003",
    productids: ["P004"],
    payment: {
      paymentid: "PAY016",
      amount: 15.99,
      transactionstatus: "pending",
    },
    shipping: {
      shippingid: "SHIP012",
      trackingno: "TRACK012",
      deliverystatus: "pending",
      address: { street: "789 Bojanala St", city: "Gaborone", district: "SE" },
    },
    quantities: [1],
  },
];

// Insert function calls
insertUsers(users);
insertCustomers(customers);
insertSellers(sellers);
insertEmployees(employees);
insertProductCategories(categories);
insertProducts(products);
insertOrders(orders);

generateInvoice("ORD-20250530-000001");
db.orders.deleteOne({ orderid: "ORD-20250530-000001" });
