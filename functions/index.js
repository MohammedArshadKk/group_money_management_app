const functions = require("firebase-functions");
const stripe = require("stripe")(functions.config().stripe.secret);

exports.createUpiPaymentIntent = functions.https.onCall(
    async (data, context) => {
      try {
        const amount = data.amount;
        const paymentIntent = await stripe.paymentIntents.create({
          amount,
          currency: "inr",
          payment_method_types: ["upi"],
        });
        return {
          clientSecret: paymentIntent.client_secret,
        };
      } catch (error) {
        throw new functions.https.HttpsError("internal", error.message);
      }
    },
);
