// Join Query
db.orders.aggregate([
  {
    $lookup: {
      from: "customers",
      localField: "customerid",
      foreignField: "customerid",
      as: "customer",
    },
  },
  { $unwind: "$customer" },
  {
    $lookup: {
      from: "users",
      localField: "customer.userid",
      foreignField: "userid",
      as: "user",
    },
  },
  { $unwind: "$user" },
  {
    $match: { "user.address.district": "SE" },
  },
  {
    $lookup: {
      from: "payments",
      localField: "payment.paymentid",
      foreignField: "paymentid",
      as: "payment_doc",
    },
  },
  {
    $unwind: {
      path: "$payment_doc",
      preserveNullAndEmptyArrays: true,
    },
  },
  {
    $lookup: {
      from: "shippings",
      localField: "shippingid",
      foreignField: "shippingid",
      as: "shipping",
    },
  },
  {
    $unwind: {
      path: "$shipping",
      preserveNullAndEmptyArrays: true,
    },
  },
  {
    $project: {
      _id: 0,
      orderid: 1,
      orderdate: 1,
      order_status: "$status",
      customer_name: "$user.name",
      customer_city: "$user.address.city",
      payment_status: "$payment_doc.transactionstatus",
      trackingno: "$shipping.trackingno",
      shipping_status: "$shipping.deliverystatus",
      shipping_city: "$shipping.address.city",
    },
  },
  { $sort: { orderdate: -1 } },
]);

// Union Query
// Customers query
const customers_agg = db.customers
  .aggregate([
    {
      $lookup: {
        from: "users",
        localField: "userid",
        foreignField: "userid",
        as: "user",
      },
    },
    { $unwind: "$user" },
    {
      $match: {
        "user.address.city": { $in: ["Gaborone", "Francistown"] },
        "user.role": "customer",
      },
    },
    {
      $project: {
        id: "$customerid",
        name: "$user.name",
        email: "$user.email",
        contact: "$user.contact",
        user_type: { $literal: "Customer" },
        city: "$user.address.city",
      },
    },
  ])
  .toArray();

const sellers_agg = db.sellers
  .aggregate([
    {
      $lookup: {
        from: "users",
        localField: "userid",
        foreignField: "userid",
        as: "user",
      },
    },
    { $unwind: "$user" },
    {
      $match: {
        "user.address.city": { $in: ["Gaborone", "Francistown"] },
        "user.role": "seller",
      },
    },
    {
      $project: {
        id: "$sellerid",
        name: "$user.name",
        email: "$user.email",
        contact: "$user.contact",
        user_type: { $literal: "Seller" },
        city: "$user.address.city",
      },
    },
  ])
  .toArray();

const combined = [...customers_agg, ...sellers_agg];
combined.sort((a, b) => {
  const cityA = a.city || "";
  const cityB = b.city || "";
  const nameA = a.name || "";
  const nameB = b.name || "";
  return cityA.localeCompare(cityB) || nameA.localeCompare(nameB);
});

combined.forEach((doc) => printjson(doc));

// Inheritance style Query
db.products.aggregate([
  {
    $match: {
      status: "available",
      "category.categoryname": { $in: ["Electronics", "Appliances"] },
    },
  },
  {
    $project: {
      productid: 1,
      productname: 1,
      price: 1,
      status: 1,
      category: "$category.categoryname",
      category_description: "$category.description",
    },
  },
  {
    $sort: {
      category: 1,
      productname: 1,
    },
  },
]);

// Temporal Query
db.orders.aggregate([
  {
    $match: {
      "payment.transactionstatus": "pending",
      orderdate: {
        $gte: new Date(new Date().setMonth(new Date().getMonth() - 6)),
      },
    },
  },
  {
    $lookup: {
      from: "customers",
      localField: "customerid",
      foreignField: "customerid",
      as: "customer",
    },
  },
  { $unwind: "$customer" },
  {
    $lookup: {
      from: "users",
      localField: "customer.userid",
      foreignField: "userid",
      as: "user",
    },
  },
  { $unwind: "$user" },
  {
    $lookup: {
      from: "shippings",
      localField: "shippingid",
      foreignField: "shippingid",
      as: "shipping",
    },
  },
  { $unwind: "$shipping" },
  { $unwind: { path: "$productid", includeArrayIndex: "productIndex" } },
  {
    $lookup: {
      from: "products",
      localField: "productid",
      foreignField: "productid",
      as: "product",
    },
  },
  { $unwind: "$product" },
  {
    $addFields: {
      processing_time: {
        $divide: [
          { $subtract: ["$shipping.updated_at", "$orderdate"] },
          1000 * 60 * 60 * 24,
        ],
      },
    },
  },
  // Group by category, customer name, and order month
  {
    $group: {
      _id: {
        category: "$product.category.categoryname",
        customer_name: "$user.name",
        order_month: { $month: "$orderdate" },
      },
      order_count: { $sum: 1 },
      avg_processing_days: { $avg: "$processing_time" },
    },
  },
  // Filter groups with order_count > 0
  { $match: { order_count: { $gt: 0 } } },
  // Project final output
  {
    $project: {
      category: "$_id.category",
      customer_name: "$_id.customer_name",
      order_month: "$_id.order_month",
      order_count: 1,
      avg_processing_days: 1,
      _id: 0,
    },
  },
  // Sort by category, customer_name, order_month
  {
    $sort: {
      category: 1,
      customer_name: 1,
      order_month: 1,
    },
  },
]);

// OLAP Query
db.orders.aggregate([
  { $match: { "payment.transactionstatus": "completed" } },
  { $unwind: "$productid" },

  {
    $lookup: {
      from: "products",
      localField: "productid",
      foreignField: "productid",
      as: "product",
    },
  },
  { $unwind: "$product" },
  {
    $lookup: {
      from: "customers",
      localField: "customerid",
      foreignField: "customerid",
      as: "customer",
    },
  },
  { $unwind: "$customer" },
  {
    $group: {
      _id: {
        category: "$product.category.categoryname",
        order_status: "$status",
      },
      order_count: { $sum: 1 },
      total_sales: { $sum: "$product.price" },
    },
  },
  {
    $match: {
      $or: [
        { "_id.category": { $ne: null }, "_id.order_status": { $ne: null } },
        { "_id.category": null, "_id.order_status": null },
      ],
    },
  },
  {
    $project: {
      category: "$_id.category",
      order_status: "$_id.order_status",
      order_count: 1,
      total_sales: 1,
      category_grouping: {
        $cond: [{ $eq: ["$_id.category", null] }, 1, 0],
      },
      status_grouping: {
        $cond: [{ $eq: ["$_id.order_status", null] }, 1, 0],
      },
      _id: 0,
    },
  },
  {
    $sort: {
      category: 1,
      order_status: 1,
    },
  },
]);
